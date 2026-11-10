defmodule KeepsakesWeb.Admin.FinanceLive.Invoice do
  @moduledoc """
  `admin.<host>/finance/invoices/:id`: one invoice (amounts, period,
  customer or their kept name and email if the account is gone), its
  payment attempts and refunds. Staff with `finance.refund` can refund a
  successful payment, fully or partly, choosing what happens to the plan.
  Needs `finance.view`.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.Admin.FinanceLive.Payments, only: [payment_status: 1]

  alias Keepsakes.Billing.Price
  alias Keepsakes.Finance
  alias Keepsakes.Staff.Scope, as: StaffScope

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:finance}>
      <.link
        navigate={~p"/finance/payments"}
        class="mb-4 flex w-fit items-center gap-1 text-sm text-ks-muted"
      >
        <.icon name="hero-arrow-left" class="size-4" /> Payments
      </.link>
      <.header>
        Invoice <span class="font-mono">{@invoice.number}</span>
        <:subtitle>
          {String.capitalize(@invoice.kind)} · {@invoice.plan.name} · {@invoice.status}
        </:subtitle>
      </.header>

      <div class="grid gap-4 lg:grid-cols-2">
        <section
          id="invoice-amounts"
          class="flex flex-col gap-2 rounded-box border border-base-300 bg-base-100 p-5 text-[15px]"
        >
          <h2 class="mb-1 font-bold">Amounts</h2>
          <.row label="Price">{money(@invoice, @invoice.subtotal_minor)}</.row>
          <.row :if={@invoice.credit_minor > 0} label="Credit for unused days">
            −{money(@invoice, @invoice.credit_minor)}
          </.row>
          <.row :if={@invoice.discount_minor > 0} label={"Discount (#{@invoice.discount_label})"}>
            −{money(@invoice, @invoice.discount_minor)}
          </.row>
          <.row label="Total">
            <span class="font-bold">{money(@invoice, @invoice.amount_minor)}</span>
          </.row>
          <.row :if={@refunded > 0} label="Refunded">−{money(@invoice, @refunded)}</.row>
          <.row :if={@invoice.period_start} label="Period">
            {date(@invoice.period_start)} – {date(@invoice.period_end)}
          </.row>
        </section>

        <section
          id="invoice-customer"
          class="flex flex-col gap-2 rounded-box border border-base-300 bg-base-100 p-5 text-[15px]"
        >
          <h2 class="mb-1 font-bold">Customer</h2>
          <p>{@invoice.billing_name}</p>
          <p class="text-ks-muted">{@invoice.billing_email}</p>
          <%= cond do %>
            <% is_nil(@invoice.user) -> %>
              <p id="deleted-customer" class="text-sm text-ks-muted">
                The account has been deleted; this record is kept for the books.
              </p>
            <% @customer_link? -> %>
              <.link
                navigate={~p"/customers/#{@invoice.user_id}"}
                class="w-fit text-sm font-bold text-primary"
              >
                Open customer
              </.link>
            <% true -> %>
          <% end %>
        </section>
      </div>

      <section id="invoice-payments" class="mt-4 rounded-box border border-base-300 bg-base-100 p-5">
        <h2 class="mb-3 font-bold">Payments</h2>
        <ul class="flex flex-col divide-y divide-base-300">
          <li
            :for={p <- @invoice.payments}
            id={"payment-#{p.id}"}
            class="flex flex-wrap items-center justify-between gap-3 py-3"
          >
            <div class="flex flex-col gap-0.5">
              <span class="font-mono text-sm">{p.tx_ref}</span>
              <span class="text-xs text-ks-muted">{date(p.inserted_at)} · {p.gateway} {p.gateway_id}</span>
              <span :if={p.failure_reason} class="text-xs text-error">{p.failure_reason}</span>
            </div>
            <div class="flex items-center gap-3">
              <.payment_status payment={p} refunded={refunded(p)} />
              <span class="tabular-nums">{Price.format(p.currency, p.amount_minor)}</span>
              <.button
                :if={@can_refund? and Finance.refundable(p) > 0}
                id={"refund-#{p.id}"}
                size="sm"
                phx-click="open_refund"
                phx-value-id={p.id}
              >
                Refund
              </.button>
            </div>
          </li>
        </ul>
      </section>

      <section
        :if={@invoice.refunds != []}
        id="invoice-refunds"
        class="mt-4 rounded-box border border-base-300 bg-base-100 p-5"
      >
        <h2 class="mb-3 font-bold">Refunds</h2>
        <ul class="flex flex-col gap-2 text-[15px]">
          <li
            :for={r <- @invoice.refunds}
            id={"refund-row-#{r.id}"}
            class="flex flex-wrap justify-between gap-3"
          >
            <span>
              {Price.format(r.currency, r.amount_minor)} · {r.reason}
              <span class="text-sm text-ks-muted">
                · {if r.plan_action == "end_now", do: "plan ended", else: "no renewal"} · by {r.staff_email}
              </span>
              <.badge :if={r.status == "pending"} variant="pending" class="ml-1">
                Waiting on the provider
              </.badge>
              <.badge :if={r.status == "failed"} variant="muted" class="ml-1">Failed</.badge>
              <span :if={r.failure_reason} class="block text-xs text-error">{r.failure_reason}</span>
            </span>
            <span class="font-mono text-xs text-ks-muted">{date(r.inserted_at)}</span>
          </li>
        </ul>
      </section>

      <.modal
        :if={@refunding}
        id="refund-dialog"
        show
        title="Refund this payment"
        subtitle={"Up to #{Price.format(@refunding.currency, Finance.refundable(@refunding))} can be refunded. The money goes back to their card through the payment provider, and they're emailed."}
        on_cancel={JS.push("close_refund")}
      >
        <.form for={@refund_form} id="refund-form" phx-submit="refund" class="flex flex-col gap-2">
          <.input
            field={@refund_form[:amount]}
            label={"Amount (#{@refunding.currency})"}
            inputmode="decimal"
            required
          />
          <.input field={@refund_form[:reason]} label="Reason" maxlength="200" required />
          <fieldset class="flex flex-col gap-2 pt-1">
            <legend class="mb-1.5 text-sm font-medium">Their plan</legend>
            <label
              :for={{label, value} <- plan_actions()}
              class="flex cursor-pointer items-start gap-2.5"
            >
              <input
                type="radio"
                name="refund[plan_action]"
                value={value}
                checked={@refund_form[:plan_action].value == value}
                class="radio radio-primary radio-sm mt-0.5"
              />
              <span>{label}</span>
            </label>
          </fieldset>
          <p :if={@refund_error} id="refund-error" class="text-sm text-error">{@refund_error}</p>
          <div class="flex justify-end gap-2.5 pt-1">
            <.button type="button" phx-click={JS.exec("data-cancel", to: "#refund-dialog")}>Cancel</.button>
            <.button id="refund-submit" variant="danger" phx-disable-with="Refunding…">Refund</.button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp row(assigns) do
    ~H"""
    <div class="flex justify-between gap-3">
      <span class="text-ks-muted">{@label}</span>
      <span class="text-right tabular-nums">{render_slot(@inner_block)}</span>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.staff_scope

    {:ok,
     socket
     |> assign(
       can_refund?: StaffScope.can?(scope, "finance.refund"),
       customers?: StaffScope.can?(scope, "users.view"),
       refunding: nil,
       refund_form: nil,
       refund_error: nil
     )
     |> load(id)}
  end

  @impl true
  def handle_event("open_refund", %{"id" => id}, socket) do
    payment = Enum.find(socket.assigns.invoice.payments, &(&1.id == id))
    left = Finance.refundable(payment)

    form =
      to_form(%{"amount" => major(left), "reason" => "", "plan_action" => "end_at_period_end"},
        as: :refund
      )

    {:noreply, assign(socket, refunding: payment, refund_form: form, refund_error: nil)}
  end

  def handle_event("close_refund", _params, socket),
    do: {:noreply, assign(socket, refunding: nil, refund_error: nil)}

  def handle_event("refund", %{"refund" => params}, socket) do
    payment = socket.assigns.refunding

    case Finance.refund(socket.assigns.staff_scope, payment, minor(params["amount"]), params) do
      {:ok, refund} ->
        {:noreply,
         socket
         |> assign(refunding: nil)
         |> load(socket.assigns.invoice.id)
         |> put_flash(:info, "Refunded #{Price.format(refund.currency, refund.amount_minor)}.")}

      {:error, reason} ->
        {:noreply,
         socket
         # A refused refund is listed as failed
         |> load(socket.assigns.invoice.id)
         |> assign(
           refund_error: error_text(reason, payment.currency),
           refund_form: to_form(params, as: :refund)
         )}
    end
  end

  defp load(socket, id) do
    invoice = Finance.get_invoice!(socket.assigns.staff_scope, id)

    assign(socket,
      invoice: invoice,
      refunded: succeeded(invoice.refunds),
      # Staff accounts aren't customers, so there's no profile to open
      customer_link?:
        socket.assigns.customers? and invoice.user != nil and
          not Keepsakes.Staff.staff?(invoice.user),
      page_title: "Invoice #{invoice.number}"
    )
  end

  defp succeeded(refunds),
    do:
      refunds
      |> Enum.filter(&(&1.status == "succeeded"))
      |> Enum.map(& &1.amount_minor)
      |> Enum.sum()

  defp plan_actions do
    [
      {"Keep it until the period ends, then no renewal", "end_at_period_end"},
      {"End it now and move them to Free", "end_now"}
    ]
  end

  defp refunded(payment), do: succeeded(payment.refunds)

  # "5000" or "12.50" (major units) -> minor units
  defp minor(value) do
    case Decimal.parse(String.replace(to_string(value), ",", "")) do
      {d, ""} -> d |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()
      _ -> nil
    end
  end

  defp major(minor) when rem(minor, 100) == 0, do: to_string(div(minor, 100))
  defp major(minor), do: :erlang.float_to_binary(minor / 100, decimals: 2)

  defp error_text(:invalid_amount, _c), do: "Enter an amount, like 5000 or 12.50."
  defp error_text({:too_much, left}, c), do: "At most #{Price.format(c, left)} can be refunded."
  defp error_text(:reason_required, _c), do: "Add a reason."
  defp error_text(:plan_action_required, _c), do: "Choose what happens to their plan."
  defp error_text(:not_refundable, _c), do: "This payment can't be refunded."
  defp error_text({:gateway, message}, _c), do: "The payment provider refused: #{message}"

  defp money(invoice, minor), do: Price.format(invoice.currency, minor)

  defp date(nil), do: "—"
  defp date(at), do: Calendar.strftime(at, "%-d %b %Y")
end
