defmodule Keepsakes.Finance do
  @moduledoc """
  Money in and out, for the Finance section of the admin portal: revenue
  totals, payments and invoices, refunds through the gateway, and CSV
  exports. Amounts stay per currency (NGN and USD are never added
  together), in minor units. Revenue is successful payments minus refunds.

  Permissions: `finance.view` to look, `finance.refund` to refund,
  `finance.export` for CSV. Invoices and payments outlive deleted accounts
  (their `user_id` goes nil); the invoice keeps `billing_name`/`email`.
  """
  import Ecto.Query

  alias Keepsakes.Accounts.User
  alias Keepsakes.Billing.{Gateway, Invoice, Notifier, Payment, Payments, Plan, Refund}
  alias Keepsakes.{Audit, Repo, Staff}
  alias Keepsakes.Staff.Scope, as: StaffScope

  @page_size 50

  ## Overview

  @doc """
  The overview numbers at `now`: `this_month` and `last_month`
  (`%{currency => net minor}`), `monthly` (`%{currency => [{first_of_month,
  net}]}` for the last 12 months), `by_plan` this month (`[{plan name,
  currency, net}]`), `refunds_this_month` and `failed_30d` (count).
  """
  def overview(%StaffScope{} = scope, now \\ DateTime.utc_now()) do
    Staff.authorize!(scope, "finance.view")

    this_month = Date.beginning_of_month(DateTime.to_date(now))
    last_month = this_month |> Date.add(-1) |> Date.beginning_of_month()

    first =
      Enum.reduce(1..11, this_month, fn _, d -> d |> Date.add(-1) |> Date.beginning_of_month() end)

    paid = monthly(paid_query(), first)
    refunded = monthly(refund_query(), first)

    months =
      Stream.iterate(first, &(&1 |> Date.add(32) |> Date.beginning_of_month())) |> Enum.take(12)

    currencies =
      (Map.keys(paid) ++ Map.keys(refunded))
      |> Enum.map(fn {currency, _month} -> currency end)
      |> Enum.concat(["NGN", "USD"])
      |> Enum.uniq()
      |> Enum.sort()

    net = fn currency, month ->
      Map.get(paid, {currency, month}, 0) - Map.get(refunded, {currency, month}, 0)
    end

    %{
      this_month: Map.new(currencies, &{&1, net.(&1, this_month)}),
      last_month: Map.new(currencies, &{&1, net.(&1, last_month)}),
      monthly: Map.new(currencies, fn c -> {c, Enum.map(months, &{&1, net.(c, &1)})} end),
      by_plan: by_plan(this_month),
      refunds_this_month: Map.new(currencies, &{&1, Map.get(refunded, {&1, this_month}, 0)}),
      failed_30d:
        Repo.aggregate(
          from(p in Payment,
            where: p.status == "failed" and p.inserted_at >= ^DateTime.add(now, -30, :day)
          ),
          :count
        )
    }
  end

  defp paid_query do
    from p in Payment,
      where: p.status == "successful",
      select: %{at: p.updated_at, currency: p.currency, amount: p.amount_minor}
  end

  defp refund_query do
    from r in succeeded_refunds(),
      select: %{at: r.inserted_at, currency: r.currency, amount: r.amount_minor}
  end

  # Money out: only refunds the gateway made
  defp succeeded_refunds, do: from(r in Refund, where: r.status == "succeeded")

  defp refunded_by_payment do
    from r in succeeded_refunds(),
      group_by: r.payment_id,
      select: %{payment_id: r.payment_id, amount: sum(r.amount_minor)}
  end

  # %{{currency, first_of_month} => minor} since `first`
  defp monthly(query, first) do
    since = DateTime.new!(first, ~T[00:00:00], "Etc/UTC")

    from(q in subquery(query),
      where: q.at >= ^since,
      group_by: [q.currency, fragment("date_trunc('month', ?)::date", q.at)],
      select: {q.currency, fragment("date_trunc('month', ?)::date", q.at), sum(q.amount)}
    )
    |> Repo.all()
    |> Map.new(fn {currency, month, sum} -> {{currency, month}, to_int(sum)} end)
  end

  defp by_plan(month) do
    since = DateTime.new!(month, ~T[00:00:00], "Etc/UTC")

    from(p in Payment,
      join: i in assoc(p, :invoice),
      join: plan in Plan,
      on: plan.id == i.plan_id,
      left_join: r in subquery(refunded_by_payment()),
      on: r.payment_id == p.id,
      where: p.status == "successful" and p.updated_at >= ^since,
      group_by: [plan.name, plan.position, p.currency],
      order_by: [asc: plan.position, asc: p.currency],
      select: {plan.name, p.currency, sum(p.amount_minor - coalesce(r.amount, 0))}
    )
    |> Repo.all()
    |> Enum.map(fn {name, currency, sum} -> {name, currency, to_int(sum)} end)
  end

  ## Payments

  @statuses [
    {"Successful", "successful"},
    {"Failed", "failed"},
    {"Pending", "pending"},
    {"Refunded", "refunded"}
  ]

  @doc "Status filter options."
  def statuses, do: @statuses

  @doc """
  Payments, newest first, `#{@page_size}` per page. Filters: `"status"`
  (see `statuses/0`; "refunded" means at least partly), `"currency"`,
  `"from"`/`"to"` (ISO dates, inclusive) and `"q"` (customer email,
  invoice number or our tx_ref). Returns `{rows, more?}`; each row is
  `%{id, payment, invoice, refunded_minor}`.
  """
  def list_payments(%StaffScope{} = scope, filters \\ %{}, page \\ 0) do
    Staff.authorize!(scope, "finance.view")

    rows =
      payments_query(filters)
      |> order_by([p], desc: p.inserted_at, desc: p.id)
      |> offset(^(page * @page_size))
      |> limit(^(@page_size + 1))
      |> Repo.all()
      |> Enum.map(fn {payment, invoice, refunded} ->
        %{id: payment.id, payment: payment, invoice: invoice, refunded_minor: to_int(refunded)}
      end)

    {Enum.take(rows, @page_size), length(rows) > @page_size}
  end

  defp payments_query(filters) do
    from(p in Payment,
      as: :payment,
      join: i in assoc(p, :invoice),
      as: :invoice,
      left_join: r in subquery(refunded_by_payment()),
      as: :refunds,
      on: r.payment_id == p.id,
      select: {p, i, coalesce(r.amount, 0)}
    )
    |> filter(:status, filters["status"])
    |> filter(:currency, filters["currency"])
    |> filter(:from, date(filters["from"]))
    |> filter(:to, date(filters["to"]))
    |> filter(:q, filters["q"])
  end

  defp filter(query, _key, value) when value in [nil, ""], do: query
  defp filter(query, :status, "refunded"), do: where(query, [refunds: r], not is_nil(r.amount))
  defp filter(query, :status, status), do: where(query, [payment: p], p.status == ^status)
  defp filter(query, :currency, c), do: where(query, [payment: p], p.currency == ^c)

  defp filter(query, :from, %Date{} = d),
    do: where(query, [payment: p], p.inserted_at >= ^DateTime.new!(d, ~T[00:00:00], "Etc/UTC"))

  defp filter(query, :to, %Date{} = d),
    do: where(query, [payment: p], p.inserted_at <= ^DateTime.new!(d, ~T[23:59:59], "Etc/UTC"))

  defp filter(query, :q, q) do
    like = "%" <> String.replace(String.trim(q), ~r/[\\%_]/, "\\\\\\0") <> "%"

    where(
      query,
      [payment: p, invoice: i],
      ilike(i.billing_email, ^like) or ilike(i.number, ^like) or ilike(p.tx_ref, ^like)
    )
  end

  defp date(value) when value in [nil, ""], do: nil

  defp date(value) do
    case Date.from_iso8601(to_string(value)) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  ## Invoices

  @doc "An invoice with its plan, price, customer (nil once deleted), payments and refunds."
  def get_invoice!(%StaffScope{} = scope, id) do
    Staff.authorize!(scope, "finance.view")

    Repo.one!(
      from i in Invoice,
        where: i.id == ^id,
        preload: [
          :plan,
          :price,
          :user,
          payments: ^from(p in Payment, order_by: p.inserted_at, preload: :refunds),
          refunds: ^from(r in Refund, order_by: r.inserted_at)
        ]
    )
  end

  @doc """
  How much of a payment can still be refunded (minor units). Refunds still
  waiting on the gateway count, so the same money can't be refunded twice.
  """
  def refundable(%Payment{status: "successful"} = payment) do
    refunded =
      Repo.one(
        from r in Refund,
          where: r.payment_id == ^payment.id and r.status in ["pending", "succeeded"],
          select: sum(r.amount_minor)
      )

    payment.amount_minor - to_int(refunded)
  end

  def refundable(_payment), do: 0

  ## Refunds

  @plan_actions %{"end_now" => :end_now, "end_at_period_end" => :end_at_period_end}

  @doc """
  Refunds `amount_minor` of a successful payment through the gateway,
  with a `reason` and `plan_action` (`"end_now"` or
  `"end_at_period_end"`).

  The refund is saved as `pending` before the gateway is asked, so one the
  gateway made can't go unrecorded. When the gateway accepts, it becomes
  `succeeded`, the plan is handled, the change is audited and the customer
  is emailed; when it refuses, it becomes `failed` and nothing else happens.
  """
  def refund(%StaffScope{} = scope, %Payment{} = payment, amount_minor, %{} = opts) do
    Staff.authorize!(scope, "finance.refund")
    payment = Repo.preload(payment, :invoice, force: true)
    reason = String.trim(opts["reason"] || "")
    plan_action = opts["plan_action"]

    cond do
      payment.status != "successful" or is_nil(payment.gateway_id) ->
        {:error, :not_refundable}

      not is_integer(amount_minor) or amount_minor <= 0 ->
        {:error, :invalid_amount}

      reason == "" ->
        {:error, :reason_required}

      not Map.has_key?(@plan_actions, plan_action) ->
        {:error, :plan_action_required}

      true ->
        with {:ok, pending} <- start_refund(scope, payment, amount_minor, reason, plan_action) do
          case Gateway.adapter().refund(payment.gateway_id, amount_minor) do
            :ok ->
              {:ok, refund} = finish_refund(scope, payment, pending)
              notify(payment.invoice, refund)
              {:ok, refund}

            {:error, error} ->
              message = gateway_message(error)

              pending
              |> Ecto.Changeset.change(
                status: "failed",
                failure_reason: String.slice(message, 0, 255)
              )
              |> Repo.update!()

              {:error, {:gateway, message}}
          end
        end
    end
  end

  # Checks what's left and saves the pending refund under a lock on the
  # payment, so two staff can't refund the same money at once
  defp start_refund(scope, payment, amount, reason, plan_action) do
    Repo.transact(fn ->
      Repo.one!(from p in Payment, where: p.id == ^payment.id, lock: "FOR UPDATE")
      left = refundable(payment)

      if amount > left do
        {:error, {:too_much, left}}
      else
        {:ok,
         Repo.insert!(%Refund{
           payment_id: payment.id,
           invoice_id: payment.invoice.id,
           amount_minor: amount,
           currency: payment.currency,
           reason: reason,
           plan_action: plan_action,
           staff_id: scope.user.id,
           staff_email: scope.user.email
         })}
      end
    end)
  end

  defp finish_refund(scope, payment, pending) do
    invoice = payment.invoice

    Repo.transact(fn ->
      refund = pending |> Ecto.Changeset.change(status: "succeeded") |> Repo.update!()

      if payment.user_id,
        do:
          Payments.end_after_refund(
            payment.user_id,
            Map.fetch!(@plan_actions, refund.plan_action)
          )

      Audit.record(scope, "payment.refunded", {"invoice", invoice.id, invoice.number}, %{
        "amount" => refund.amount_minor,
        "currency" => refund.currency,
        "reason" => refund.reason,
        "plan" => refund.plan_action,
        "customer" => invoice.billing_email
      })

      {:ok, refund}
    end)
  end

  # The account may be gone; the invoice still says who paid
  defp notify(invoice, refund) do
    user =
      (invoice.user_id && Repo.get(User, invoice.user_id)) ||
        %User{first_name: invoice.billing_name || "there", email: invoice.billing_email}

    if user.email, do: Notifier.deliver_refund(user, invoice, refund)
  end

  defp gateway_message({:rejected, message}) when is_binary(message), do: message
  defp gateway_message({:http, status, %{"message" => message}}), do: "#{message} (#{status})"
  defp gateway_message({:http, status, _body}), do: "The payment provider answered #{status}"
  defp gateway_message(other), do: "The payment provider couldn't be reached (#{inspect(other)})"

  ## CSV

  @doc """
  Payments between `from` and `to` (dates, inclusive) as CSV lines (the
  header first), with what's been refunded. Needs `finance.export`; audited.
  """
  def payments_csv(%StaffScope{} = scope, from, to) do
    Staff.authorize!(scope, "finance.export")
    audit_export(scope, "payments", from, to)

    rows =
      payments_query(%{"from" => from, "to" => to})
      |> order_by([p], asc: p.inserted_at)
      |> Repo.all()
      |> Enum.map(fn {p, i, refunded} ->
        [
          DateTime.to_iso8601(p.inserted_at),
          i.number,
          i.billing_name,
          i.billing_email,
          i.kind,
          p.status,
          p.currency,
          money(p.amount_minor),
          money(to_int(refunded)),
          i.discount_label,
          p.gateway,
          p.tx_ref,
          p.gateway_id,
          p.failure_reason
        ]
      end)

    csv([
      ~w(date invoice name email kind status currency amount refunded discount gateway tx_ref gateway_id failure)
      | rows
    ])
  end

  @doc """
  Refunds (every attempt, with its status) between `from` and `to` as CSV
  lines. Needs `finance.export`; audited.
  """
  def refunds_csv(%StaffScope{} = scope, from, to) do
    Staff.authorize!(scope, "finance.export")
    audit_export(scope, "refunds", from, to)

    rows =
      from(r in Refund, join: i in assoc(r, :invoice), order_by: r.inserted_at, select: {r, i})
      |> between(date(from), date(to))
      |> Repo.all()
      |> Enum.map(fn {r, i} ->
        [
          DateTime.to_iso8601(r.inserted_at),
          i.number,
          i.billing_email,
          r.currency,
          money(r.amount_minor),
          r.status,
          r.plan_action,
          r.reason,
          r.staff_email,
          r.failure_reason
        ]
      end)

    csv([~w(date invoice email currency amount status plan reason staff failure) | rows])
  end

  defp between(query, from, to) do
    query =
      if from,
        do: where(query, [r], r.inserted_at >= ^DateTime.new!(from, ~T[00:00:00], "Etc/UTC")),
        else: query

    if to,
      do: where(query, [r], r.inserted_at <= ^DateTime.new!(to, ~T[23:59:59], "Etc/UTC")),
      else: query
  end

  defp audit_export(scope, what, from, to),
    do:
      Audit.record(scope, "finance.exported", nil, %{"what" => what, "from" => from, "to" => to})

  defp money(minor), do: :erlang.float_to_binary(minor / 100, decimals: 2)

  # RFC 4180: quote every field that needs it; formulas are neutralised so a
  # spreadsheet never runs a customer's name
  defp csv(rows), do: Enum.map(rows, &(Enum.map_join(&1, ",", fn v -> field(v) end) <> "\r\n"))

  defp field(nil), do: ""

  defp field(value) do
    value = to_string(value)
    value = if String.starts_with?(value, ~w(= + - @)), do: "'" <> value, else: value

    if String.contains?(value, [",", "\"", "\n", "\r"]),
      do: "\"" <> String.replace(value, "\"", "\"\"") <> "\"",
      else: value
  end

  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(nil), do: 0
  defp to_int(n), do: n
end
