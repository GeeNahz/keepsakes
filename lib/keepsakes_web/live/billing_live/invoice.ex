defmodule KeepsakesWeb.BillingLive.Invoice do
  @moduledoc "`/billing/invoices/:id`: a receipt the owner can read or print."
  use KeepsakesWeb, :live_view

  alias Keepsakes.Billing
  alias Keepsakes.Billing.Price

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} owner={@owner}>
      <div class="mx-auto flex w-full max-w-[640px] flex-col gap-6">
        <div class="flex items-center justify-between gap-4 print:hidden">
          <.link id="invoice-back" navigate={~p"/billing"} class="text-sm font-medium no-underline">
            ← Plans &amp; billing
          </.link>
          <.button id="print-receipt" size="sm" phx-click={JS.dispatch("ks:print")}>
            <.icon name="hero-printer" class="size-4" /> Print
          </.button>
        </div>

        <article
          id="receipt"
          class="flex flex-col gap-6 rounded-2xl border border-base-300 bg-base-100 p-8 print:border-0 print:p-0"
        >
          <div class="flex items-start justify-between gap-4">
            <.logo />
            <div class="flex flex-col items-end gap-1 text-right">
              <span class="text-sm font-bold uppercase tracking-[0.06em] text-ks-muted">
                {if @invoice.status == "paid", do: "Receipt", else: "Invoice"}
              </span>
              <span id="receipt-number" class="font-mono">{@invoice.number}</span>
            </div>
          </div>

          <div class="grid gap-1 text-sm">
            <span class="font-bold">{Keepsakes.Accounts.User.full_name(@current_scope.user)}</span>
            <span class="text-ks-muted">{@current_scope.user.email}</span>
          </div>

          <div class="flex flex-col gap-3 border-y border-base-300 py-5 text-[15px]">
            <div class="flex justify-between gap-3">
              <span>
                {@invoice.plan.name} plan, {if @invoice.price.interval == "month",
                  do: "monthly",
                  else: "yearly"}
                <span :if={@invoice.period_start} class="block text-sm text-ks-muted">
                  {date(@invoice.period_start)} – {date(@invoice.period_end)}
                </span>
              </span>
              <span>{Price.format(@invoice.currency, @invoice.subtotal_minor)}</span>
            </div>
            <div :if={@invoice.credit_minor > 0} class="flex justify-between gap-3">
              <span class="text-ks-muted">Credit for unused days of the previous plan</span>
              <span>−{Price.format(@invoice.currency, @invoice.credit_minor)}</span>
            </div>
          </div>

          <div class="flex justify-between gap-3 text-lg font-bold">
            <span>{if @invoice.status == "paid", do: "Paid", else: "Due"}</span>
            <span id="receipt-amount">{Price.format(@invoice.currency, @invoice.amount_minor)}</span>
          </div>

          <p :if={@invoice.paid_at} class="text-sm text-ks-muted">
            Paid on {date(@invoice.paid_at)} by card through Flutterwave{reference(@invoice)}.
          </p>
        </article>
      </div>
    </Layouts.app>
    """
  end

  defp reference(%{payments: [%{gateway_id: id} | _]}) when is_binary(id),
    do: " (transaction #{id})"

  defp reference(_invoice), do: ""

  defp date(at), do: Calendar.strftime(at, "%-d %B %Y")

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    invoice = Billing.get_invoice!(socket.assigns.current_scope, id)
    {:ok, assign(socket, page_title: "Receipt #{invoice.number}", invoice: invoice)}
  end
end
