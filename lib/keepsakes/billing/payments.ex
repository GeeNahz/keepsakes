defmodule Keepsakes.Billing.Payments do
  @moduledoc """
  Taking money for paid plans (called through `Keepsakes.Billing`).

  **Checkout.** `quote_price/3` decides what choosing a price means: upgrades
  (a higher plan, or monthly → yearly) start now, with unused days of the
  current paid period credited off the charge; downgrades and other
  changes wait for the next renewal. Paying during the trial keeps the
  trial's remaining days: the first period ends one interval after the
  trial would have. `start_checkout/3` records an open invoice and a
  pending payment, then sends the customer to the gateway's card page.

  **Confirming.** The return page, the webhook and the pending-payment
  check all call `confirm/2`, which asks the gateway (never trusting the
  redirect or webhook body) and, when the charge succeeded for the right
  amount and currency, fulfils it once: payment and invoice paid, plan and
  period updated, card saved, receipt emailed.

  **Renewals** (`renew_due/1` and friends, run hourly by
  `Keepsakes.Billing.advance/1`): at the end of each period the saved card
  is charged. A failed charge makes the subscription `past_due` with full
  access, retried 1, 3 and 5 days after the first failure; then 7 days of
  grace; then Free. Cancelling stops renewal and moves to Free at the end
  of the paid period.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Keepsakes.Accounts.{Scope, User}
  alias Keepsakes.Billing.{Charge, Gateway, Invoice, Notifier, Payment, PaymentMethod}
  alias Keepsakes.Billing.{PaymentEvent, Plan, Price, Quote, Subscription, SubscriptionEvent}
  alias Keepsakes.Billing.{DiscountCode, DiscountRedemption, Discounts, WebhookWorker}
  alias Keepsakes.{Repo, Settings}

  # Below this (₦1 / $1) a credited upgrade waits for renewal instead
  @min_charge_minor 100

  # Retries after a failed renewal, counted from the first failure
  @retry_after_days [1, 3, 5]

  # Pending payments are re-checked after this long, and given up after a day
  @pending_check_after_minutes 15
  @pending_give_up_after_hours 24

  ## Quotes and checkout

  @doc """
  What choosing `price` costs now (see `Keepsakes.Billing.Quote`).

  Options: `:code` - a discount code the customer typed; `:now`. Without a
  code, a discount the subscription already has still applies when it
  covers the plan. Free months earned through referrals lengthen the
  first paid period.
  """
  @spec quote_price(Scope.t(), Price.t(), keyword()) ::
          {:ok, Quote.t()}
          | {:error, :not_paid_plan | :current_plan | {:code, Discounts.problem() | atom()}}
  def quote_price(%Scope{user: user}, %Price{} = price, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:second) end)
    typed = opts |> Keyword.get(:code) |> blank_to_nil()
    price = Repo.preload(price, :plan)
    subscription = subscription_for(user.id)

    cond do
      price.plan.kind != "paid" or not price.active ->
        {:error, :not_paid_plan}

      paying?(subscription) and subscription.price_id == price.id ->
        {:error, :current_plan}

      paying?(subscription) and not upgrade?(subscription.price, price) ->
        if typed, do: {:error, {:code, :not_now}}, else: {:ok, scheduled(subscription, price)}

      true ->
        with {:ok, discount} <- discount_for(typed, user.id, subscription, price, now) do
          checkout_quote(subscription, price, discount, now)
        end
    end
  end

  # {percent, label, new code or nil}, from a typed code or the discount
  # the subscription already has
  defp discount_for(nil, _user_id, subscription, price, now) do
    redemption = subscription && subscription.discount_redemption

    case Discounts.active(redemption, price.plan, now) do
      nil -> {:ok, nil}
      r -> {:ok, {r.percent_off, Discounts.label(r.discount_code.code, r.percent_off), nil}}
    end
  end

  defp discount_for(typed, user_id, _subscription, price, now) do
    case Discounts.check(typed, user_id, price, now) do
      {:ok, code} -> {:ok, {code.percent_off, Discounts.label(code.code, code.percent_off), code}}
      {:error, problem} -> {:error, {:code, problem}}
    end
  end

  defp checkout_quote(subscription, price, discount, now) do
    {percent, label, code} = discount || {0, nil, nil}
    discount_minor = Discounts.amount_off(price.amount_minor, percent)
    credit = min(credit(subscription, price, now), price.amount_minor - discount_minor)
    amount = price.amount_minor - discount_minor - credit
    free_months = (subscription && subscription.user.free_months_banked) || 0

    cond do
      # A credited upgrade that leaves (almost) nothing to pay waits for renewal
      amount < @min_charge_minor and paying?(subscription) and is_nil(code) ->
        {:ok, scheduled(subscription, price)}

      # Card payments need an amount; a 100% code can't start a card plan
      amount < @min_charge_minor ->
        {:error, {:code, :too_much}}

      true ->
        {:ok,
         %Quote{
           mode: :checkout,
           price: price,
           subtotal_minor: price.amount_minor,
           discount_minor: discount_minor,
           discount_label: label,
           discount_code: code,
           credit_minor: credit,
           amount_minor: amount,
           free_months: free_months,
           period_end:
             subscription |> period_end(price, now) |> DateTime.shift(month: free_months)
         }}
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # On a paid plan in good standing (credit and scheduling apply)
  defp paying?(%Subscription{status: "active", plan: %Plan{kind: "paid"}, price: %Price{}}),
    do: true

  defp paying?(_subscription), do: false

  defp upgrade?(%Price{} = current, %Price{} = next) do
    current = Repo.preload(current, :plan)

    cond do
      next.plan.position > current.plan.position -> true
      next.plan_id == current.plan_id -> current.interval == "month" and next.interval == "year"
      true -> false
    end
  end

  defp scheduled(subscription, price) do
    %Quote{mode: :scheduled, price: price, starts_at: subscription.current_period_end}
  end

  # Unused share of the paid part of the current period, in the new price's
  # currency, rounded down to a whole naira/dollar. Trial days folded into
  # the period aren't paid for, so they don't count; they carry over instead
  # (see period_end/3).
  defp credit(subscription, %Price{currency: currency}, now) do
    with true <- paying?(subscription),
         %Price{currency: ^currency, amount_minor: paid} <- subscription.price,
         %DateTime{} = period_start <- subscription.current_period_start,
         %DateTime{} = ends <- subscription.current_period_end,
         starts = latest(period_start, subscription.trial_ends_at),
         total when total > 0 <- DateTime.diff(ends, starts),
         left when left > 0 <- DateTime.diff(ends, latest(now, starts)) do
      div(div(paid * min(left, total), total), 100) * 100
    else
      _ -> 0
    end
  end

  defp latest(at, nil), do: at
  defp latest(at, other), do: if(DateTime.after?(other, at), do: other, else: at)

  # Paying (or upgrading) before the trial would have ended keeps its
  # remaining days: the period runs one interval past the trial's end
  defp period_end(%Subscription{trial_ends_at: %DateTime{} = trial_end}, price, now) do
    if DateTime.after?(trial_end, now),
      do: add_interval(trial_end, price.interval),
      else: add_interval(now, price.interval)
  end

  defp period_end(_subscription, price, now), do: add_interval(now, price.interval)

  @doc "`at` plus one billing interval."
  def add_interval(%DateTime{} = at, "month"), do: DateTime.shift(at, month: 1)
  def add_interval(%DateTime{} = at, "year"), do: DateTime.shift(at, year: 1)

  @doc """
  Acts on choosing `price`: for a `:checkout` quote, records the invoice and
  payment and returns `{:ok, {:redirect, url}}` to the gateway's card page;
  for a `:scheduled` one, books the change for the next renewal and returns
  `{:ok, {:scheduled, quote}}`.
  """
  @spec start_checkout(Scope.t(), Price.t(), String.t()) ::
          {:ok, {:redirect, String.t()} | {:scheduled, Quote.t()}} | {:error, term()}
  def start_checkout(%Scope{user: user} = scope, %Price{} = price, redirect_url, opts \\ []) do
    with {:ok, quote} <- quote_price(scope, price, Keyword.take(opts, [:code])) do
      case quote.mode do
        :scheduled -> schedule_change(user, quote)
        :checkout -> open_checkout(user, quote, redirect_url)
      end
    end
  end

  defp schedule_change(user, quote) do
    subscription = subscription_for(user.id)

    Multi.new()
    |> Multi.update(
      :subscription,
      Ecto.Changeset.change(subscription, pending_price_id: quote.price.id)
    )
    |> Multi.insert(
      :event,
      event(subscription, "change_scheduled", to_plan: quote.price.plan.slug)
    )
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        Keepsakes.Billing.broadcast_change(user.id)
        {:ok, {:scheduled, quote}}

      {:error, _, reason, _} ->
        {:error, reason}
    end
  end

  defp open_checkout(user, quote, redirect_url) do
    subscription = subscription_for(user.id)

    {:ok, %{payment: payment}} =
      Multi.new()
      |> Multi.insert(:invoice, %Invoice{
        user_id: user.id,
        subscription_id: subscription && subscription.id,
        number: next_invoice_number(),
        kind: "checkout",
        plan_id: quote.price.plan_id,
        price_id: quote.price.id,
        currency: quote.price.currency,
        subtotal_minor: quote.subtotal_minor,
        discount_minor: quote.discount_minor,
        discount_label: quote.discount_label,
        # Only a newly typed code; one already in use stays on the subscription
        discount_code_id: quote.discount_code && quote.discount_code.id,
        credit_minor: quote.credit_minor,
        amount_minor: quote.amount_minor
      })
      |> Multi.insert(:payment, &new_payment(&1.invoice))
      |> Repo.transaction()

    checkout = %{
      tx_ref: payment.tx_ref,
      amount_minor: payment.amount_minor,
      currency: payment.currency,
      email: user.email,
      name: User.full_name(user),
      redirect_url: redirect_url,
      title: "Keepsake",
      description: "#{quote.price.plan.name} · #{interval_name(quote.price.interval)}"
    }

    case Gateway.adapter().init_checkout(checkout) do
      {:ok, %{link: link}} ->
        {:ok, {:redirect, link}}

      {:error, reason} ->
        fail(payment, "Couldn't start checkout: #{inspect(reason)}")
        {:error, :gateway_unavailable}
    end
  end

  @doc "The customer cancelled on the card page: void the attempt."
  @spec abandon(String.t()) :: :ok
  def abandon(tx_ref) do
    case Repo.get_by(Payment, tx_ref: tx_ref, status: "pending") do
      %Payment{} = payment -> fail(payment, "Cancelled at checkout")
      nil -> :ok
    end
  end

  ## Confirming

  @doc """
  Confirms the payment with reference `tx_ref` by asking the gateway (by its
  transaction ID when known, else by our reference) and fulfils it when it
  succeeded. Safe to call any number of times.
  """
  @spec confirm(String.t(), String.t() | nil) ::
          {:ok, :paid | :pending} | {:error, :unknown | :failed | :mismatch | term()}
  def confirm(tx_ref, gateway_id \\ nil) do
    with %Payment{} = payment <- Repo.get_by(Payment, tx_ref: tx_ref) |> Repo.preload(:invoice),
         {:payment, "pending"} <- {:payment, payment.status},
         {:ok, %Charge{} = charge} <- lookup(tx_ref, gateway_id) do
      apply_charge(payment, charge)
    else
      nil -> {:error, :unknown}
      {:payment, "successful"} -> {:ok, :paid}
      {:payment, "failed"} -> {:error, :failed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lookup(tx_ref, nil), do: Gateway.adapter().verify_by_reference(tx_ref)
  defp lookup(_tx_ref, gateway_id), do: Gateway.adapter().verify(gateway_id)

  defp apply_charge(%Payment{} = payment, %Charge{} = charge) do
    cond do
      charge.tx_ref != payment.tx_ref ->
        {:error, :mismatch}

      charge.status == :pending ->
        {:ok, :pending}

      charge.status == :failed ->
        fail(payment, charge.message || "Declined", charge.raw)
        {:error, :failed}

      charge.currency != payment.currency or (charge.amount_minor || 0) < payment.amount_minor ->
        fail(
          payment,
          "Paid #{charge.amount_minor} #{charge.currency}, expected " <>
            "#{payment.amount_minor} #{payment.currency}",
          charge.raw
        )

        {:error, :mismatch}

      true ->
        fulfil(payment, charge)
    end
  end

  # Marks everything paid and moves the plan on, once: the payment row is
  # locked, and a second caller finds it already successful.
  defp fulfil(%Payment{id: payment_id}, %Charge{} = charge) do
    now = DateTime.utc_now(:second)

    Repo.transaction(fn ->
      payment =
        Repo.one!(from p in Payment, where: p.id == ^payment_id, lock: "FOR UPDATE")
        |> Repo.preload(invoice: [price: :plan])

      if payment.status == "successful" do
        :already
      else
        do_fulfil(payment, charge, now)
      end
    end)
    |> case do
      {:ok, :already} ->
        {:ok, :paid}

      {:ok, {user, invoice, method, referrer}} ->
        Keepsakes.Billing.broadcast_change(user.id)
        Notifier.deliver_receipt(user, invoice, method)

        with {referrer, reward} <- referrer do
          Keepsakes.Billing.broadcast_change(referrer.id)
          Notifier.deliver_referral_reward(referrer, user, reward)
        end

        {:ok, :paid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_fulfil(payment, charge, now) do
    %Invoice{price: price} = invoice = payment.invoice

    subscription =
      Repo.one!(from s in Subscription, where: s.user_id == ^payment.user_id, lock: "FOR UPDATE")

    subscription = Repo.preload(subscription, [:plan, :price, :discount_redemption])
    user = Repo.one!(from u in User, where: u.id == ^payment.user_id, lock: "FOR UPDATE")

    {period_start, period_end} =
      case invoice.kind do
        "checkout" ->
          # Free months earned through referrals are spent here
          {now,
           subscription
           |> period_end(price, now)
           |> DateTime.shift(month: user.free_months_banked)}

        "renewal" ->
          start = subscription.current_period_end || now
          {start, add_interval(start, price.interval)}
      end

    if invoice.kind == "checkout" and user.free_months_banked > 0,
      do: user |> Ecto.Changeset.change(free_months_banked: 0) |> Repo.update!()

    redemption = settle_discount(invoice, subscription, period_start, now)

    payment
    |> Ecto.Changeset.change(status: "successful", gateway_id: charge.gateway_id, raw: charge.raw)
    |> Repo.update!()

    invoice =
      invoice
      |> Ecto.Changeset.change(
        status: "paid",
        paid_at: now,
        period_start: period_start,
        period_end: period_end
      )
      |> Repo.update!()

    from_status = subscription.status
    from_plan = subscription.plan.slug

    subscription
    |> Ecto.Changeset.change(
      plan_id: price.plan_id,
      price_id: price.id,
      pending_price_id: nil,
      status: "active",
      current_period_start: period_start,
      current_period_end: period_end,
      cancel_at_period_end: false,
      grace_ends_at: nil,
      retry_count: 0,
      next_retry_at: nil,
      discount_redemption_id: redemption && redemption.id
    )
    |> Repo.update!()

    Repo.insert!(%SubscriptionEvent{
      subscription_id: subscription.id,
      kind: if(invoice.kind == "renewal", do: "renewed", else: "plan_started"),
      from_status: from_status,
      to_status: "active",
      from_plan: from_plan,
      to_plan: price.plan.slug
    })

    # Other open invoices (an earlier abandoned checkout, a renewal still
    # being retried) are settled by this payment
    from(i in Invoice,
      where: i.user_id == ^payment.user_id and i.status == "open" and i.id != ^invoice.id
    )
    |> Repo.update_all(set: [status: "void", updated_at: now])

    method =
      if charge.card,
        do: save_card(payment.user_id, charge.card),
        else: payment_method(payment.user_id)

    referrer = reward_referrer(user, now)
    {user, %{invoice | price: price, plan: price.plan}, method, referrer}
  end

  # The discount the subscription carries after this payment: a newly typed
  # code is redeemed now; a `once` discount ends with the invoice it covered
  defp settle_discount(invoice, subscription, period_start, now) do
    redemption =
      case invoice.discount_code_id do
        nil ->
          subscription.discount_redemption

        code_id ->
          Discounts.redeem(Repo.get!(DiscountCode, code_id), invoice.user_id, period_start)
      end

    case redemption do
      %DiscountRedemption{duration: "once"} = r when invoice.discount_minor > 0 ->
        Discounts.finish(r, now)

      other ->
        other
    end
  end

  # A referred user's first payment earns their inviter a month: added to
  # the current paid period, or banked for their first one. Once per
  # referred user (referral_rewarded_at).
  defp reward_referrer(%User{referred_by_id: nil}, _now), do: nil
  defp reward_referrer(%User{referral_rewarded_at: %DateTime{}}, _now), do: nil

  defp reward_referrer(%User{} = user, now) do
    user |> Ecto.Changeset.change(referral_rewarded_at: now) |> Repo.update!()

    referrer = Repo.one(from u in User, where: u.id == ^user.referred_by_id, lock: "FOR UPDATE")
    subscription = referrer && subscription_for(referrer.id)

    cond do
      is_nil(referrer) ->
        nil

      paying?(subscription) and subscription.current_period_end ->
        extended = DateTime.shift(subscription.current_period_end, month: 1)

        subscription
        |> Ecto.Changeset.change(current_period_end: extended)
        |> Repo.update!()

        Repo.insert!(event(subscription, "referral_month", to_plan: subscription.plan.slug))
        {referrer, {:extended, extended}}

      true ->
        referrer
        |> Ecto.Changeset.change(free_months_banked: referrer.free_months_banked + 1)
        |> Repo.update!()

        {referrer, :banked}
    end
  end

  defp save_card(user_id, card) do
    %PaymentMethod{user_id: user_id}
    |> Ecto.Changeset.change(
      gateway: Gateway.name(),
      token: card.token,
      brand: card.brand,
      last4: card.last4,
      expiry: card.expiry,
      email: card.email || Repo.get!(User, user_id).email
    )
    |> Repo.insert!(
      on_conflict: {:replace, [:gateway, :token, :brand, :last4, :expiry, :email, :updated_at]},
      conflict_target: :user_id
    )
  end

  defp fail(%Payment{} = payment, reason, raw \\ nil) do
    payment = Repo.preload(payment, :invoice)

    Multi.new()
    |> Multi.update_all(
      :payment,
      from(p in Payment, where: p.id == ^payment.id and p.status == "pending"),
      set: [
        status: "failed",
        failure_reason: String.slice(reason, 0, 250),
        raw: raw || payment.raw,
        updated_at: DateTime.utc_now(:second)
      ]
    )
    # A checkout nobody finished is void; a renewal stays open for retries
    |> Multi.update_all(
      :invoice,
      from(i in Invoice,
        where: i.id == ^payment.invoice_id and i.kind == "checkout" and i.status == "open"
      ),
      set: [status: "void", updated_at: DateTime.utc_now(:second)]
    )
    |> Repo.transaction()

    :ok
  end

  ## Webhooks

  @doc """
  Takes a webhook: checks it came from the gateway, stores it once (repeats
  hit the unique index) and queues `Keepsakes.Billing.WebhookWorker` to
  confirm the payment. Returns `{:error, :invalid}` for a bad signature.
  """
  @spec receive_webhook([{String.t(), String.t()}], map()) :: :ok | {:error, :invalid}
  def receive_webhook(headers, body) do
    gateway = Gateway.adapter()

    if gateway.valid_webhook?(headers) do
      with {:ok, event} <- gateway.parse_webhook(body) do
        now = DateTime.utc_now(:second)

        row = %{
          id: Ecto.UUID.generate(),
          gateway: gateway.name(),
          event_id: event.id,
          event_type: event.type,
          payload: body,
          inserted_at: now
        }

        Multi.new()
        |> Multi.insert_all(:event, PaymentEvent, [row],
          on_conflict: :nothing,
          conflict_target: [:gateway, :event_id],
          returning: [:id]
        )
        |> Multi.run(:job, fn _repo, %{event: inserted} ->
          case inserted do
            {1, [%{id: id}]} -> Oban.insert(WebhookWorker.new(%{payment_event_id: id}))
            {0, _} -> {:ok, :repeat}
          end
        end)
        |> Repo.transaction()
      end

      :ok
    else
      {:error, :invalid}
    end
  end

  @doc false
  # WebhookWorker: confirms the payment the event is about. Gateway outages
  # return an error so Oban retries; anything else marks the event handled.
  def process_event(event_id) do
    with %PaymentEvent{processed_at: nil} = event <- Repo.get(PaymentEvent, event_id),
         {:ok, %{tx_ref: tx_ref, gateway_id: gateway_id}} when is_binary(tx_ref) <-
           Gateway.adapter().parse_webhook(event.payload) do
      case confirm(tx_ref, gateway_id) do
        {:error, reason} when reason not in [:unknown, :failed, :mismatch] ->
          {:error, reason}

        _handled ->
          event
          |> Ecto.Changeset.change(processed_at: DateTime.utc_now(:second))
          |> Repo.update!()

          :ok
      end
    else
      _ -> :ok
    end
  end

  ## Renewals (run hourly from Billing.advance/1)

  @doc "Moves cancelled subscriptions whose paid period has ended to Free."
  def end_cancelled(now) do
    free = Repo.get_by!(Plan, slug: "free")

    from(s in Subscription,
      join: p in assoc(s, :plan),
      where: p.kind == "paid" and s.status == "active" and s.cancel_at_period_end,
      where: s.current_period_end <= ^now,
      preload: [:user, :plan]
    )
    |> Repo.all()
    |> Enum.count(fn subscription ->
      move_to_free(subscription, free, "cancelled_to_free")
    end)
  end

  @doc "Charges the saved card for every paid period that has ended."
  def renew_due(now) do
    from(s in Subscription,
      join: p in assoc(s, :plan),
      join: u in assoc(s, :user),
      where: p.kind == "paid" and s.status == "active" and not s.cancel_at_period_end,
      where: s.current_period_end <= ^now,
      # Accounts paused for deletion aren't charged
      where: is_nil(u.deletion_requested_at),
      preload: [:user, :plan, :price, :pending_price]
    )
    |> Repo.all()
    |> Enum.reject(&charge_in_flight?/1)
    |> Enum.count(&(attempt_renewal(&1, now) == :paid))
  end

  @doc "Retries failed renewals that are due, moving to grace after the last."
  def retry_due(now) do
    from(s in Subscription,
      join: u in assoc(s, :user),
      where: s.status == "past_due" and s.next_retry_at <= ^now,
      where: is_nil(u.deletion_requested_at),
      preload: [:user, :plan, :price, :pending_price]
    )
    |> Repo.all()
    |> Enum.reject(&charge_in_flight?/1)
    |> Enum.count(&(attempt_renewal(&1, now) == :paid))
  end

  # A renewal charge the gateway hasn't settled yet; check_pending/1 will
  defp charge_in_flight?(%Subscription{id: id}) do
    from(p in Payment,
      join: i in assoc(p, :invoice),
      where: i.subscription_id == ^id and i.kind == "renewal" and p.status == "pending"
    )
    |> Repo.exists?()
  end

  defp attempt_renewal(subscription, now) do
    price = subscription.pending_price || subscription.price
    invoice = open_renewal_invoice(subscription, price)
    payment = Repo.insert!(new_payment(invoice))

    result =
      case payment_method(subscription.user_id) do
        nil ->
          {:ok, %Charge{tx_ref: payment.tx_ref, status: :failed, message: "No card on file"}}

        method ->
          Gateway.adapter().charge_token(%{
            token: method.token,
            email: method.email,
            amount_minor: payment.amount_minor,
            currency: payment.currency,
            tx_ref: payment.tx_ref
          })
      end

    case result do
      {:ok, %Charge{status: :successful} = charge} ->
        case apply_charge(payment, charge) do
          {:ok, :paid} -> :paid
          _ -> renewal_failed(subscription, now)
        end

      {:ok, %Charge{status: :pending}} ->
        :pending

      {:ok, %Charge{} = charge} ->
        fail(payment, charge.message || "Declined", charge.raw)
        renewal_failed(subscription, now)

      # Gateway unreachable: leave the payment pending for check_pending/1
      {:error, _reason} ->
        :pending
    end
  end

  defp open_renewal_invoice(subscription, price) do
    Repo.one(
      from i in Invoice,
        where:
          i.subscription_id == ^subscription.id and i.kind == "renewal" and i.status == "open",
        limit: 1
    ) || new_renewal_invoice(subscription, Repo.preload(price, :plan))
  end

  # A discount still running for the period about to start comes off
  defp new_renewal_invoice(subscription, price) do
    subscription = Repo.preload(subscription, discount_redemption: :discount_code)
    period_start = subscription.current_period_end || DateTime.utc_now(:second)

    {discount_minor, label} =
      case Discounts.active(subscription.discount_redemption, price.plan, period_start) do
        nil ->
          {0, nil}

        r ->
          {Discounts.amount_off(price.amount_minor, r.percent_off),
           Discounts.label(r.discount_code.code, r.percent_off)}
      end

    Repo.insert!(%Invoice{
      user_id: subscription.user_id,
      subscription_id: subscription.id,
      number: next_invoice_number(),
      kind: "renewal",
      plan_id: price.plan_id,
      price_id: price.id,
      currency: price.currency,
      subtotal_minor: price.amount_minor,
      discount_minor: discount_minor,
      discount_label: label,
      amount_minor: price.amount_minor - discount_minor
    })
  end

  # First failure: past_due, retry tomorrow. Later ones: next retry day, or
  # grace once the retries are used up.
  defp renewal_failed(%Subscription{} = subscription, now) do
    attempts = if subscription.status == "past_due", do: subscription.retry_count + 1, else: 0
    first_failure = if attempts == 0, do: now, else: first_failure_at(subscription, now)

    case Enum.at(@retry_after_days, attempts) do
      nil ->
        grace_ends_at = DateTime.add(now, Settings.get(:grace_days), :day)

        transition(subscription, "renewal_failed_grace",
          status: "grace",
          grace_ends_at: grace_ends_at,
          next_retry_at: nil
        )

        Notifier.deliver_renewal_grace(subscription.user, grace_ends_at)

      days ->
        next = DateTime.add(first_failure, days, :day)

        transition(subscription, "renewal_failed",
          status: "past_due",
          retry_count: attempts,
          next_retry_at: next
        )

        if attempts == 0, do: Notifier.deliver_payment_failed(subscription.user, next)
    end

    :failed
  end

  # Retries count from the first failure: next_retry_at minus its offset
  defp first_failure_at(
         %Subscription{next_retry_at: %DateTime{} = next, retry_count: count},
         _now
       ),
       do: DateTime.add(next, -Enum.at(@retry_after_days, count), :day)

  defp first_failure_at(_subscription, now), do: now

  @doc "Re-checks payments the gateway left pending; gives up after a day."
  def check_pending(now) do
    check_before = DateTime.add(now, -@pending_check_after_minutes, :minute)
    give_up_before = DateTime.add(now, -@pending_give_up_after_hours, :hour)

    from(p in Payment,
      where: p.status == "pending" and p.inserted_at <= ^check_before,
      preload: [invoice: [subscription: [:user, :plan]]]
    )
    |> Repo.all()
    |> Enum.count(fn payment ->
      case confirm(payment.tx_ref) do
        {:ok, :paid} ->
          true

        # A renewal declined after all: same path as an immediate decline
        {:error, :failed} ->
          if payment.invoice.kind == "renewal" and payment.invoice.subscription,
            do: renewal_failed(payment.invoice.subscription, now)

          false

        _ ->
          payment = Repo.reload!(payment)

          if payment.status == "pending" and DateTime.before?(payment.inserted_at, give_up_before),
            do: fail(payment, "Not confirmed by the gateway within a day")

          false
      end
    end)
  end

  ## Cancel / resume

  @doc "Stops renewal; the plan stays until the end of the paid period."
  def cancel(%Scope{user: user}) do
    case subscription_for(user.id) do
      %Subscription{status: "active", plan: %Plan{kind: "paid"}, cancel_at_period_end: false} = s ->
        transition(s, "cancel_requested", cancel_at_period_end: true)

      _ ->
        {:error, :not_cancellable}
    end
  end

  @doc "Undoes `cancel/1` before the period ends."
  def resume(%Scope{user: user}) do
    case subscription_for(user.id) do
      %Subscription{status: "active", cancel_at_period_end: true} = s ->
        transition(s, "resumed", cancel_at_period_end: false)

      _ ->
        {:error, :not_cancelled}
    end
  end

  @doc "Drops a downgrade booked for the next renewal."
  def cancel_scheduled_change(%Scope{user: user}) do
    case subscription_for(user.id) do
      %Subscription{pending_price_id: id} = s when not is_nil(id) ->
        transition(s, "change_cancelled", pending_price_id: nil)

      _ ->
        {:error, :nothing_scheduled}
    end
  end

  ## Reads

  @doc "The card renewals are charged to, or nil."
  def payment_method(user_id), do: Repo.get_by(PaymentMethod, user_id: user_id)

  @doc "The user's paid and open invoices, newest first."
  def list_invoices(%Scope{user: user}) do
    from(i in Invoice,
      where: i.user_id == ^user.id and i.status in ["paid", "open"],
      order_by: [desc: i.inserted_at],
      preload: [:plan, :price]
    )
    |> Repo.all()
  end

  @doc "The user's invoice with `id`. Raises when it isn't theirs."
  def get_invoice!(%Scope{user: user}, id) do
    Repo.one!(
      from i in Invoice,
        where: i.user_id == ^user.id and i.id == ^id,
        preload: [:plan, :price, payments: ^from(p in Payment, where: p.status == "successful")]
    )
  end

  ## Helpers

  defp subscription_for(user_id) do
    Repo.one(
      from s in Subscription,
        where: s.user_id == ^user_id,
        preload: [
          :plan,
          :user,
          price: :plan,
          pending_price: :plan,
          discount_redemption: :discount_code
        ]
    )
  end

  defp new_payment(%Invoice{} = invoice) do
    %Payment{
      invoice_id: invoice.id,
      user_id: invoice.user_id,
      gateway: Gateway.name(),
      tx_ref:
        "ks-" <> (:crypto.strong_rand_bytes(12) |> Base.encode32(case: :lower, padding: false)),
      amount_minor: invoice.amount_minor,
      currency: invoice.currency
    }
  end

  defp next_invoice_number do
    %{rows: [[n]]} = Repo.query!("SELECT nextval('invoice_number_seq')")
    "KS-" <> String.pad_leading(Integer.to_string(n), 6, "0")
  end

  defp move_to_free(subscription, free, kind) do
    result =
      transition(subscription, kind,
        status: "active",
        plan_id: free.id,
        price_id: nil,
        pending_price_id: nil,
        cancel_at_period_end: false,
        current_period_start: nil,
        current_period_end: nil
      )

    case result do
      {:ok, _} ->
        Notifier.deliver_moved_to_free(subscription.user)
        true

      _ ->
        false
    end
  end

  # Applies `changes` and records the event. Conditional on the row still
  # being as we read it (status and updated_at), so overlapping runs don't
  # act twice.
  defp transition(%Subscription{} = subscription, kind, changes) do
    changes = Keyword.put(changes, :updated_at, DateTime.utc_now(:second))

    Multi.new()
    |> Multi.update_all(
      :subscription,
      from(s in Subscription,
        where:
          s.id == ^subscription.id and s.status == ^subscription.status and
            s.updated_at == ^subscription.updated_at,
        select: s
      ),
      set: changes
    )
    |> Multi.run(:event, fn repo, %{subscription: result} ->
      case result do
        {1, [updated]} ->
          updated = repo.preload(updated, :plan)

          repo.insert(%SubscriptionEvent{
            subscription_id: subscription.id,
            kind: kind,
            from_status: subscription.status,
            to_status: updated.status,
            from_plan: subscription.plan && subscription.plan.slug,
            to_plan: updated.plan.slug
          })

        _ ->
          {:error, :changed_meanwhile}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{subscription: {1, [updated]}}} ->
        Keepsakes.Billing.broadcast_change(updated.user_id)
        {:ok, updated}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp event(subscription, kind, fields) do
    struct(
      %SubscriptionEvent{
        subscription_id: subscription.id,
        kind: kind,
        from_status: subscription.status,
        to_status: subscription.status,
        from_plan: subscription.plan.slug
      },
      fields
    )
  end

  defp interval_name("month"), do: "monthly"
  defp interval_name("year"), do: "yearly"
end
