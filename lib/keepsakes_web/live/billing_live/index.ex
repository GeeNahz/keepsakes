defmodule KeepsakesWeb.BillingLive.Index do
  @moduledoc """
  `/app/billing`: the owner's plan, what they're using against its limits, the
  card renewals are charged to, invoices, and the plans side by side in
  NGN or USD, monthly or yearly.

  Choosing a plan first shows what it means (`Billing.quote_price/2`):
  what's due today with any credit for unused days, or that a downgrade
  waits for the next renewal. Paying continues on Flutterwave's card page,
  which returns to `/app/billing/return`. The page reloads when a payment is
  confirmed (also from a webhook). Becomes the Billing tab of settings in
  Stage 6.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.{Albums, Billing, Entitlements, Format}
  alias Keepsakes.Billing.{Discounts, Features, PaymentMethod, Price, Quote}
  alias KeepsakesWeb.OwnerShell

  # Rows in the plan comparison: the features that are live today
  @compared ~w(max_albums max_memories_per_album storage_bytes max_upload_mb
               premium_templates guest_downloads remove_branding)a

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} owner={@owner}>
      <div class="mx-auto flex w-full max-w-[1040px] flex-col gap-8">
        <div class="flex flex-col gap-1.5">
          <h1 class="text-[32px] font-bold">Plans &amp; billing</h1>
          <p class="text-base text-ks-muted">
            Your plan, what you're using, and what each plan includes.
          </p>
        </div>

        <section
          id="current-plan"
          aria-label="Your plan"
          class="grid gap-6 rounded-2xl border border-base-300 bg-base-100 p-7 md:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)]"
        >
          <div class="flex flex-col gap-2">
            <span class="text-sm font-bold uppercase tracking-[0.06em] text-ks-muted">Your plan</span>
            <span id="current-plan-name" class="text-2xl font-bold">{@plan.name}</span>
            <span
              :if={Billing.status_detail(@subscription)}
              id="current-plan-status"
              class="text-[15px] font-medium text-primary"
            >
              {Billing.status_detail(@subscription)}
            </span>
            <p class="text-sm leading-relaxed text-ks-muted">{plan_note(@subscription)}</p>

            <.billing_details
              subscription={@subscription}
              payment_method={@payment_method}
            />
          </div>

          <div id="usage" class="flex flex-col gap-4">
            <.usage_row
              id="usage-storage"
              label="Storage"
              used={@usage.storage_bytes}
              limit={@limits.storage_bytes}
              format={&Format.bytes/1}
            />
            <.usage_row
              id="usage-albums"
              label="Albums"
              used={@usage.max_albums}
              limit={@limits.max_albums}
            />
            <.usage_row
              id="usage-photos"
              label="Photos in your largest album"
              used={@usage.max_memories_per_album}
              limit={@limits.max_memories_per_album}
            />
          </div>
        </section>

        <section id="plans" aria-label="Plans" class="flex flex-col gap-5">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <h2 class="text-2xl font-bold">Plans</h2>
            <div class="flex flex-wrap gap-3">
              <.segmented
                id="currency-switch"
                event="currency"
                value={@currency}
                options={[{"NGN", "₦ NGN"}, {"USD", "$ USD"}]}
              />
              <.segmented
                id="interval-switch"
                event="interval"
                value={@interval}
                options={[{"month", "Monthly"}, {"year", "Yearly"}]}
              />
            </div>
          </div>

          <div class="grid gap-5 md:grid-cols-3">
            <.plan_card
              :for={plan <- @plans}
              plan={plan}
              price={Billing.price(plan, @currency, @interval)}
              subscription={@subscription}
              current={plan.id == @plan.id}
              compared={@compared}
            />
          </div>
          <p class="text-sm text-ks-muted">
            Pay by card in naira or dollars. Plans renew automatically; cancel any time.
          </p>
        </section>

        <section
          id="referrals"
          aria-label="Invite friends"
          class="grid gap-5 rounded-2xl border border-base-300 bg-base-100 p-7 md:grid-cols-[minmax(0,1fr)_auto]"
        >
          <div class="flex flex-col gap-2">
            <h2 class="text-xl font-bold">Invite friends, get a free month</h2>
            <p class="text-sm leading-relaxed text-ks-muted">
              Share your link. When someone joins with it and chooses a plan, you get a month free.
            </p>
            <div class="mt-2 flex flex-wrap gap-2">
              <input
                id="referral-link"
                type="text"
                readonly
                value={url(~p"/auth/register?ref=#{@referrals.code}")}
                class="input h-11 min-w-0 flex-1 border-ks-field bg-base-200 font-mono text-sm"
              />
              <.button
                id="copy-referral"
                type="button"
                variant="secondary"
                phx-click={JS.dispatch("ks:copy", detail: %{from: "#referral-link"})}
              >
                <span data-copy-label>Copy link</span>
              </.button>
            </div>
          </div>
          <dl id="referral-stats" class="grid grid-cols-3 gap-4 self-center text-center md:w-72">
            <div class="flex flex-col gap-1">
              <dt class="text-xs text-ks-muted">Joined</dt>
              <dd class="text-2xl font-bold tabular-nums">{@referrals.joined}</dd>
            </div>
            <div class="flex flex-col gap-1">
              <dt class="text-xs text-ks-muted">Months earned</dt>
              <dd class="text-2xl font-bold tabular-nums">{@referrals.paid}</dd>
            </div>
            <div class="flex flex-col gap-1">
              <dt class="text-xs text-ks-muted">Waiting</dt>
              <dd class="text-2xl font-bold tabular-nums">{@referrals.banked}</dd>
            </div>
          </dl>
        </section>

        <section :if={@invoices != []} id="invoices" aria-label="Invoices" class="flex flex-col gap-4">
          <h2 class="text-2xl font-bold">Invoices</h2>
          <div class="overflow-x-auto rounded-2xl border border-base-300 bg-base-100">
            <table class="table">
              <thead>
                <tr class="text-ks-muted">
                  <th>Number</th>
                  <th>Date</th>
                  <th>Plan</th>
                  <th class="text-right">Amount</th>
                  <th>Status</th>
                  <th><span class="sr-only">Receipt</span></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={invoice <- @invoices} id={"invoice-#{invoice.id}"}>
                  <td class="font-mono text-sm">{invoice.number}</td>
                  <td>{date(invoice.paid_at || invoice.inserted_at)}</td>
                  <td>{invoice.plan.name} · {interval_name(invoice.price.interval)}</td>
                  <td class="text-right tabular-nums">
                    {Price.format(invoice.currency, invoice.amount_minor)}
                  </td>
                  <td>
                    <span class={[
                      "badge badge-sm",
                      if(invoice.status == "paid", do: "badge-primary", else: "badge-warning")
                    ]}>
                      {if invoice.status == "paid", do: "Paid", else: "Due"}
                    </span>
                  </td>
                  <td class="text-right">
                    <.link
                      :if={invoice.status == "paid"}
                      navigate={~p"/app/billing/invoices/#{invoice.id}"}
                      class="text-sm font-bold"
                    >
                      Receipt
                    </.link>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>

      <.modal
        :if={@quote}
        id="checkout-dialog"
        title={"#{@quote.price.plan.name} · #{interval_name(@quote.price.interval)}"}
        show
        on_cancel={JS.push("close_quote")}
      >
        <.quote_summary quote={@quote} subscription={@subscription} />
        <form
          :if={@quote.mode == :checkout or @code_error}
          id="discount-form"
          phx-submit="apply_code"
          class="flex flex-col gap-1.5"
        >
          <label for="discount-code" class="text-sm font-medium">Have a code?</label>
          <div class="flex gap-2">
            <input
              id="discount-code"
              name="code"
              type="text"
              value={@code}
              autocomplete="off"
              autocapitalize="characters"
              spellcheck="false"
              placeholder="e.g. LAUNCH20"
              class="input h-11 flex-1 border-ks-field bg-base-100 font-mono uppercase"
            />
            <.button id="apply-code" type="submit" size="sm" class="h-11">Apply</.button>
          </div>
          <p :if={@code_error} id="code-error" class="text-sm text-error">{@code_error}</p>
        </form>
        <div class="flex justify-end gap-2.5 pt-1">
          <.button type="button" phx-click={JS.push("close_quote")}>Not now</.button>
          <.button
            id="confirm-plan"
            variant="primary"
            phx-click="confirm_plan"
            phx-disable-with={if @quote.mode == :checkout, do: "Opening payment…", else: "Saving…"}
          >
            {if @quote.mode == :checkout, do: "Continue to payment", else: "Confirm switch"}
          </.button>
        </div>
      </.modal>
    </Layouts.app>
    """
  end

  attr :subscription, :any, required: true
  attr :payment_method, :any, required: true

  # Price, renewal or end date, card, and what can be done about them
  defp billing_details(assigns) do
    ~H"""
    <div
      :if={paid?(@subscription)}
      id="billing-details"
      class="mt-2 flex flex-col gap-3 border-t border-base-300 pt-4 text-sm"
    >
      <div :if={@subscription.price} class="flex justify-between gap-3">
        <span class="text-ks-muted">Price</span>
        <span class="font-medium">
          {Price.format(@subscription.price)} / {@subscription.price.interval}
        </span>
      </div>
      <div :if={@subscription.current_period_end} class="flex justify-between gap-3">
        <span class="text-ks-muted">
          {if @subscription.cancel_at_period_end, do: "Ends on", else: "Renews on"}
        </span>
        <span class="font-medium">{date(@subscription.current_period_end)}</span>
      </div>
      <div :if={@payment_method} id="card-on-file" class="flex justify-between gap-3">
        <span class="text-ks-muted">Card</span>
        <span class="font-medium">{PaymentMethod.label(@payment_method)}</span>
      </div>
      <div
        :if={active_discount(@subscription)}
        id="active-discount"
        class="flex justify-between gap-3"
      >
        <span class="text-ks-muted">Discount</span>
        <span class="text-right font-medium">{active_discount(@subscription)}</span>
      </div>

      <p
        :if={@subscription.pending_price}
        id="scheduled-change"
        class="rounded-field bg-ks-teal-soft p-3 text-ks-muted"
      >
        Switching to {@subscription.pending_price.plan.name} ({interval_name(
          @subscription.pending_price.interval
        )}, {Price.format(@subscription.pending_price)}) on {date(@subscription.current_period_end)}.
        <button
          id="keep-current-plan"
          type="button"
          phx-click="cancel_scheduled_change"
          class="cursor-pointer font-bold text-primary"
        >
          Keep my current plan
        </button>
      </p>

      <p
        :if={@subscription.status in ["past_due", "grace"]}
        id="payment-problem"
        class="rounded-field bg-ks-amber-soft p-3 text-ks-amber-deep"
      >
        Your last renewal didn't go through. Pay with a card now to keep your plan.
      </p>

      <div class="flex flex-wrap gap-2.5 pt-1">
        <.button
          :if={@subscription.status in ["past_due", "grace"] and @subscription.price}
          id="pay-now"
          variant="primary"
          size="sm"
          phx-click="choose"
          phx-value-price={@subscription.price.id}
        >
          Pay now
        </.button>
        <.button
          :if={@subscription.status == "active" and not @subscription.cancel_at_period_end}
          id="cancel-plan"
          size="sm"
          phx-click="cancel_plan"
        >
          Cancel plan
        </.button>
        <.button
          :if={@subscription.status == "active" and @subscription.cancel_at_period_end}
          id="resume-plan"
          variant="primary"
          size="sm"
          phx-click="resume_plan"
        >
          Keep my plan
        </.button>
      </div>
    </div>
    """
  end

  attr :quote, Quote, required: true
  attr :subscription, :any, required: true

  defp quote_summary(%{quote: %Quote{mode: :scheduled}} = assigns) do
    ~H"""
    <p id="quote-summary" class="text-[15px] leading-relaxed text-ks-muted">
      Nothing to pay today. You'll move to {@quote.price.plan.name} at {Price.format(@quote.price)} a {@quote.price.interval} on {date(
        @quote.starts_at
      )},
      when your current period ends. Until then nothing changes.
    </p>
    """
  end

  defp quote_summary(assigns) do
    ~H"""
    <div id="quote-summary" class="flex flex-col gap-3 text-[15px]">
      <div class="flex justify-between gap-3">
        <span class="text-ks-muted">{@quote.price.plan.name}, {interval_name(@quote.price.interval)}</span>
        <span>{Price.format(@quote.price.currency, @quote.subtotal_minor)}</span>
      </div>
      <div :if={@quote.discount_minor > 0} id="quote-discount" class="flex justify-between gap-3">
        <span class="text-ks-muted">{@quote.discount_label}</span>
        <span>−{Price.format(@quote.price.currency, @quote.discount_minor)}</span>
      </div>
      <div :if={@quote.credit_minor > 0} id="quote-credit" class="flex justify-between gap-3">
        <span class="text-ks-muted">Credit for unused days of your current plan</span>
        <span>−{Price.format(@quote.price.currency, @quote.credit_minor)}</span>
      </div>
      <div class="flex justify-between gap-3 border-t border-base-300 pt-3 font-bold">
        <span>Due today</span>
        <span id="quote-amount">{Price.format(@quote.price.currency, @quote.amount_minor)}</span>
      </div>
      <p id="quote-terms" class="text-sm leading-relaxed text-ks-muted">
        {terms(@quote, @subscription)}
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :used, :integer, required: true
  attr :limit, :any, required: true
  attr :format, :any, default: &Integer.to_string/1

  defp usage_row(%{limit: :unlimited} = assigns) do
    ~H"""
    <div id={@id} class="flex items-center justify-between gap-3 text-sm">
      <span class="font-medium">{@label}</span>
      <span class="text-ks-muted">{@format.(@used)} · unlimited</span>
    </div>
    """
  end

  defp usage_row(assigns) do
    ~H"""
    <.meter
      id={@id}
      label={@label}
      value={min(@used, @limit)}
      max={max(@limit, 1)}
      text={"#{@format.(@used)} of #{@format.(@limit)}"}
    />
    <p :if={@used > @limit} class="-mt-2 text-[13px] text-ks-amber-deep">
      Over the limit: nothing is removed, but you can't add more here.
    </p>
    """
  end

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :value, :string, required: true
  attr :options, :list, required: true

  defp segmented(assigns) do
    ~H"""
    <div
      id={@id}
      role="group"
      class="flex gap-0.5 rounded-full border border-base-300 bg-base-100 p-1"
    >
      <button
        :for={{value, label} <- @options}
        type="button"
        phx-click={@event}
        phx-value-to={value}
        aria-pressed={to_string(value == @value)}
        class="min-h-9 cursor-pointer rounded-full px-3.5 text-sm font-bold text-ks-muted transition-colors aria-pressed:bg-primary aria-pressed:text-primary-content"
      >
        {label}
      </button>
    </div>
    """
  end

  attr :plan, :map, required: true
  attr :price, :any, required: true
  attr :subscription, :any, required: true
  attr :current, :boolean, required: true
  attr :compared, :list, required: true

  defp plan_card(assigns) do
    assigns =
      assign(assigns,
        action: plan_action(assigns.subscription, assigns.plan, assigns.price),
        rows:
          for feature <- assigns.compared do
            value = Features.value(assigns.plan.features, feature.key)
            %{key: feature.key, text: feature_text(feature, value), on?: value not in [false, 0]}
          end
      )

    ~H"""
    <article
      id={"plan-#{@plan.slug}"}
      class={[
        "flex flex-col gap-5 rounded-2xl border bg-base-100 p-6",
        if(@current, do: "border-primary ring-1 ring-primary", else: "border-base-300")
      ]}
    >
      <div class="flex flex-col gap-1.5">
        <div class="flex items-center gap-2">
          <h3 class="text-xl font-bold">{@plan.name}</h3>
          <span :if={@current} class="badge badge-sm badge-primary">Current</span>
        </div>
        <p class="min-h-[2.8em] text-sm text-ks-muted">{@plan.description}</p>
      </div>

      <div class="flex items-baseline gap-1.5">
        <%= if @price do %>
          <span class="text-3xl font-bold">{Price.format(@price)}</span>
          <span class="text-sm text-ks-muted">/ {@price.interval}</span>
        <% else %>
          <span class="text-3xl font-bold">Free</span>
        <% end %>
      </div>

      <ul class="flex flex-col gap-2.5 text-sm">
        <li :for={row <- @rows} id={"plan-#{@plan.slug}-#{row.key}"} class="flex items-start gap-2">
          <.icon
            name={if row.on?, do: "hero-check", else: "hero-minus"}
            class={["mt-0.5 size-4 shrink-0", if(row.on?, do: "text-primary", else: "text-ks-field")]}
          />
          <span class={!row.on? && "text-ks-muted"}>{row.text}</span>
        </li>
      </ul>

      <div class="mt-auto">
        <%= case @action do %>
          <% :current -> %>
            <.button id={"choose-#{@plan.slug}"} type="button" class="w-full" disabled>
              Your plan
            </.button>
          <% {:choose, label} -> %>
            <.button
              id={"choose-#{@plan.slug}"}
              type="button"
              variant="primary"
              class="w-full"
              phx-click="choose"
              phx-value-price={@price.id}
            >
              {label}
            </.button>
          <% nil -> %>
        <% end %>
      </div>
    </article>
    """
  end

  # What a plan card's button does for this subscriber
  # The Free card: nothing to buy; moving down to it is "Cancel plan"
  defp plan_action(%{plan: %{kind: "free"}}, %{kind: "free"}, nil), do: :current
  defp plan_action(_subscription, _plan, nil), do: nil

  defp plan_action(subscription, plan, price) do
    cond do
      paid?(subscription) and subscription.status == "active" and
          subscription.price_id == price.id ->
        :current

      paid?(subscription) and subscription.plan_id == plan.id ->
        {:choose, "Switch to #{interval_name(price.interval)}"}

      paid?(subscription) and plan.position > subscription.plan.position ->
        {:choose, "Upgrade to #{plan.name}"}

      paid?(subscription) ->
        {:choose, "Switch to #{plan.name}"}

      true ->
        {:choose, "Choose #{plan.name}"}
    end
  end

  defp paid?(%{plan: %{kind: "paid"}}), do: true
  defp paid?(_subscription), do: false

  defp trial_left?(%{trial_ends_at: %DateTime{} = ends}),
    do: DateTime.after?(ends, DateTime.utc_now())

  defp trial_left?(_subscription), do: false

  defp terms(quote, subscription) do
    "#{quote.price.plan.name} starts now and runs until #{date(quote.period_end)}" <>
      "#{extras_note(quote, subscription)}, then renews at #{renewal_price(quote)} a " <>
      "#{quote.price.interval} until you cancel. You'll pay securely on Flutterwave's card page."
  end

  defp active_discount(%{discount_redemption: %{ended_at: nil} = r}) do
    code = r.discount_code.code

    case r do
      %{duration: "forever"} -> "#{code} · #{r.percent_off}% off, ongoing"
      %{ends_at: %DateTime{} = ends} -> "#{code} · #{r.percent_off}% off until #{date(ends)}"
      _ -> "#{code} · #{r.percent_off}% off"
    end
  end

  defp active_discount(_subscription), do: nil

  # What makes the first period longer than one interval
  defp extras_note(quote, subscription) do
    parts =
      Enum.filter(
        [
          trial_left?(subscription) && "your remaining trial days",
          quote.free_months == 1 && "1 free month from referrals",
          quote.free_months > 1 && "#{quote.free_months} free months from referrals"
        ],
        & &1
      )

    case parts do
      [] -> ""
      parts -> " (including #{Enum.join(parts, " and ")})"
    end
  end

  # Renewals keep a discount that lasts beyond the first payment
  defp renewal_price(%Quote{discount_code: %{duration: "once"}} = quote),
    do: Price.format(quote.price)

  defp renewal_price(%Quote{discount_minor: discount} = quote) when discount > 0 do
    discounted = Price.format(quote.price.currency, quote.subtotal_minor - discount)

    case quote.discount_code do
      %{duration: "repeating"} ->
        "#{discounted} while your discount lasts, then #{Price.format(quote.price)}"

      _ ->
        "#{discounted} (with your discount)"
    end
  end

  defp renewal_price(quote), do: Price.format(quote.price)

  defp feature_text(%{key: :max_albums}, :unlimited), do: "Unlimited albums"
  defp feature_text(%{key: :max_albums}, 1), do: "1 album"
  defp feature_text(%{key: :max_albums}, count), do: "#{count} albums"
  defp feature_text(%{key: :max_memories_per_album}, :unlimited), do: "Unlimited photos per album"
  defp feature_text(%{key: :max_memories_per_album}, count), do: "#{count} photos per album"
  defp feature_text(%{key: :storage_bytes}, :unlimited), do: "Unlimited storage"
  defp feature_text(%{key: :storage_bytes}, bytes), do: "#{Format.bytes(bytes)} of storage"
  defp feature_text(%{key: :max_upload_mb}, mb), do: "Photos up to #{mb} MB each"
  defp feature_text(%{name: name}, _value), do: name

  defp plan_note(%{status: "trialing", trial_ends_at: ends_at}),
    do:
      "Everything in Pro until #{date(ends_at)}. After that you get #{Keepsakes.Settings.get(:grace_days)} more days of full access, then the Free plan. Nothing you've added is ever deleted."

  defp plan_note(%{status: "grace", plan: %{kind: "paid"}, grace_ends_at: ends_at}),
    do:
      "Your plan's features stay on until #{date(ends_at)} while you update your payment, then you move to the Free plan. Nothing you've added is deleted."

  defp plan_note(%{status: "grace", grace_ends_at: ends_at}),
    do:
      "You keep every feature until #{date(ends_at)}, then move to the Free plan. Nothing you've added is deleted."

  defp plan_note(%{status: "past_due", next_retry_at: %DateTime{} = next}),
    do: "We'll try your card again on #{date(next)}. You keep every feature meanwhile."

  defp plan_note(%{cancel_at_period_end: true}),
    do:
      "Your plan won't renew. You keep its features until the end of the period, then move to Free."

  defp plan_note(_subscription),
    do: "Change plans any time. Moving to a smaller plan never deletes anything."

  defp interval_name("month"), do: "monthly"
  defp interval_name("year"), do: "yearly"

  defp date(at), do: Calendar.strftime(at, "%-d %B %Y")

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Billing.subscribe(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(
       page_title: "Plans & billing",
       plans: Billing.list_public_plans(),
       currency: "NGN",
       interval: "month",
       quote: nil,
       code: "",
       code_error: nil,
       compared: Enum.filter(Features.all(), &(&1.key in @compared))
     )
     |> load_account()}
  end

  defp load_account(socket) do
    scope = socket.assigns.current_scope
    subscription = Billing.get_subscription_details(scope)
    albums = Albums.list_albums(scope)

    socket
    |> assign(
      subscription: subscription,
      plan: Billing.current_plan(scope),
      payment_method: Billing.payment_method(scope),
      invoices: Billing.list_invoices(scope),
      referrals: Billing.referrals(scope),
      limits: Entitlements.all(scope),
      usage: %{
        storage_bytes: socket.assigns.owner.storage_used,
        max_albums: length(albums),
        max_memories_per_album: Albums.largest_album_count(scope)
      }
    )
    # Show prices in the currency and interval being paid, when there is one
    |> then(fn socket ->
      case subscription do
        %{price: %Price{currency: currency, interval: interval}} ->
          assign(socket, currency: currency, interval: interval)

        _ ->
          socket
      end
    end)
  end

  @impl true
  def handle_event("currency", %{"to" => currency}, socket) when currency in ~w(NGN USD),
    do: {:noreply, assign(socket, currency: currency)}

  def handle_event("interval", %{"to" => interval}, socket) when interval in ~w(month year),
    do: {:noreply, assign(socket, interval: interval)}

  def handle_event("choose", %{"price" => price_id}, socket) do
    price =
      Enum.find_value(socket.assigns.plans, &Enum.find(&1.prices, fn p -> p.id == price_id end))

    case price && Billing.quote_price(socket.assigns.current_scope, price) do
      {:ok, quote} -> {:noreply, assign(socket, quote: quote, code: "", code_error: nil)}
      _ -> {:noreply, put_flash(socket, :error, "That plan can't be chosen right now.")}
    end
  end

  def handle_event("close_quote", _params, socket), do: {:noreply, assign(socket, quote: nil)}

  def handle_event(
        "apply_code",
        %{"code" => typed},
        %{assigns: %{quote: %Quote{} = quote}} = socket
      ) do
    scope = socket.assigns.current_scope

    case Billing.quote_price(scope, quote.price, code: typed) do
      {:ok, new_quote} ->
        {:noreply, assign(socket, quote: new_quote, code: String.trim(typed), code_error: nil)}

      {:error, {:code, problem}} ->
        {:noreply, assign(socket, code: typed, code_error: Discounts.message(problem))}

      {:error, _} ->
        {:noreply, assign(socket, code: typed, code_error: Discounts.message(:not_found))}
    end
  end

  def handle_event("confirm_plan", _params, %{assigns: %{quote: %Quote{} = quote}} = socket) do
    %{current_scope: scope} = socket.assigns
    # Only a code that was accepted for this quote goes along
    code = if quote.discount_code, do: socket.assigns.code

    case Billing.start_checkout(scope, quote.price, url(~p"/app/billing/return"), code: code) do
      {:ok, {:redirect, link}} ->
        {:noreply, redirect(socket, external: link)}

      {:ok, {:scheduled, quote}} ->
        {:noreply,
         socket
         |> assign(quote: nil)
         |> load_account()
         |> put_flash(
           :info,
           "Done. You'll move to #{quote.price.plan.name} on #{date(quote.starts_at)}."
         )}

      # The code stopped working between applying it and paying
      {:error, {:code, problem}} ->
        {:noreply, assign(socket, code_error: Discounts.message(problem))}

      {:error, :gateway_unavailable} ->
        {:noreply,
         socket
         |> assign(quote: nil)
         |> put_flash(:error, "We couldn't reach the payment provider. Please try again shortly.")}

      {:error, _reason} ->
        {:noreply,
         socket |> assign(quote: nil) |> put_flash(:error, "That plan can't be chosen right now.")}
    end
  end

  def handle_event("cancel_plan", _params, socket) do
    case Billing.cancel(socket.assigns.current_scope) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_account()
         |> put_flash(:info, "Your plan won't renew. You keep it until the end of this period.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("resume_plan", _params, socket) do
    case Billing.resume(socket.assigns.current_scope) do
      {:ok, _} ->
        {:noreply, socket |> load_account() |> put_flash(:info, "Your plan will renew as usual.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_scheduled_change", _params, socket) do
    case Billing.cancel_scheduled_change(socket.assigns.current_scope) do
      {:ok, _} ->
        {:noreply,
         socket |> load_account() |> put_flash(:info, "You'll stay on your current plan.")}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:billing_changed, _user_id}, socket),
    do: {:noreply, socket |> OwnerShell.refresh() |> load_account()}
end
