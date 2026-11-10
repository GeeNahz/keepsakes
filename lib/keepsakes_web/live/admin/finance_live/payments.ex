defmodule KeepsakesWeb.Admin.FinanceLive.Payments do
  @moduledoc """
  `admin.<host>/finance/payments`: every payment attempt, newest first,
  with filters (status, currency, dates, email / invoice / reference) kept
  in the URL, 50 at a time, and CSV exports of payments and refunds for the
  chosen dates (`finance.export`). Needs `finance.view`.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.Admin.FinanceLive.Index, only: [finance_tabs: 1]

  alias Keepsakes.Billing.Price
  alias Keepsakes.Finance
  alias Keepsakes.Staff.Scope, as: StaffScope

  @filters ~w(q status currency from to)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:finance}>
      <.header>
        Payments
        <:subtitle>Every attempt to collect an invoice: checkouts, renewals and retries.</:subtitle>
        <:actions :if={@export?}>
          <.button
            id="export-payments"
            href={~p"/finance/export/payments.csv?#{export_query(@filter_params)}"}
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> Payments CSV
          </.button>
          <.button
            id="export-refunds"
            href={~p"/finance/export/refunds.csv?#{export_query(@filter_params)}"}
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> Refunds CSV
          </.button>
        </:actions>
      </.header>

      <.finance_tabs active={:payments} />

      <.form
        for={@filters}
        id="payment-filters"
        phx-change="filter"
        phx-submit="filter"
        class="mb-4 flex flex-wrap items-end gap-3"
      >
        <div class="w-full sm:w-64">
          <.input
            field={@filters[:q]}
            type="search"
            label="Search"
            placeholder="Email, invoice or reference"
            phx-debounce="300"
            autocomplete="off"
          />
        </div>
        <div class="w-40">
          <.input
            field={@filters[:status]}
            type="select"
            label="Status"
            prompt="Any"
            options={Finance.statuses()}
          />
        </div>
        <div class="w-32">
          <.input
            field={@filters[:currency]}
            type="select"
            label="Currency"
            prompt="Both"
            options={~w(NGN USD)}
          />
        </div>
        <div class="w-40"><.input field={@filters[:from]} type="date" label="From" /></div>
        <div class="w-40"><.input field={@filters[:to]} type="date" label="To" /></div>
      </.form>

      <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
        <table class="table">
          <thead>
            <tr>
              <th>When</th>
              <th>Customer</th>
              <th>Invoice</th>
              <th>Status</th>
              <th class="text-right">Amount</th>
            </tr>
          </thead>
          <tbody id="payments" phx-update="stream">
            <tr id="payments-empty" class="hidden only:table-row">
              <td colspan="5" class="py-10 text-center text-ks-muted">No payments match.</td>
            </tr>
            <tr
              :for={{id, row} <- @streams.payments}
              id={id}
              class="transition-colors hover:bg-base-200"
            >
              <td class="whitespace-nowrap font-mono text-[13px]">
                {Calendar.strftime(row.payment.inserted_at, "%d %b %Y, %H:%M")}
              </td>
              <td>
                <p class="text-[15px]">{row.invoice.billing_name}</p>
                <p class="text-sm text-ks-muted">{row.invoice.billing_email || "Deleted account"}</p>
              </td>
              <td>
                <.link
                  navigate={~p"/finance/invoices/#{row.invoice.id}"}
                  class="font-mono text-sm font-bold text-primary"
                >
                  {row.invoice.number}
                </.link>
                <p class="text-xs text-ks-muted">{row.invoice.kind}</p>
              </td>
              <td>
                <.payment_status payment={row.payment} refunded={row.refunded_minor} />
                <p :if={row.payment.failure_reason} class="max-w-56 truncate text-xs text-ks-muted">
                  {row.payment.failure_reason}
                </p>
              </td>
              <td class="text-right tabular-nums">
                {Price.format(row.payment.currency, row.payment.amount_minor)}
                <p :if={row.refunded_minor > 0} class="text-xs text-ks-muted">
                  −{Price.format(row.payment.currency, row.refunded_minor)} refunded
                </p>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@more?} class="mt-4 flex justify-center">
        <.button id="load-more-payments" phx-click="more" phx-disable-with="Loading…">Load more</.button>
      </div>
    </Layouts.app>
    """
  end

  attr :payment, :map, required: true
  attr :refunded, :integer, default: 0

  @doc "A payment's status badge (fully or partly refunded shown as such)."
  def payment_status(assigns) do
    ~H"""
    <%= cond do %>
      <% @refunded > 0 and @refunded >= @payment.amount_minor -> %>
        <.badge variant="muted">Refunded</.badge>
      <% @refunded > 0 -> %>
        <.badge variant="pending">Partly refunded</.badge>
      <% @payment.status == "successful" -> %>
        <.badge variant="ready">Paid</.badge>
      <% @payment.status == "failed" -> %>
        <span class="badge h-auto rounded-full border-0 bg-error/15 px-2.5 py-1 text-xs font-bold text-error">
          Failed
        </span>
      <% true -> %>
        <.badge variant="muted">Pending</.badge>
    <% end %>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Payments",
       export?: StaffScope.can?(socket.assigns.staff_scope, "finance.export")
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.new(@filters, &{&1, params[&1] || ""})
    {:noreply, load(socket, filters, 0, reset: true)}
  end

  @impl true
  def handle_event("filter", %{"payments" => params}, socket) do
    query = params |> Map.take(@filters) |> Enum.reject(fn {_k, v} -> v == "" end)
    {:noreply, push_patch(socket, to: ~p"/finance/payments?#{query}", replace: true)}
  end

  def handle_event("more", _params, socket) do
    {:noreply, load(socket, socket.assigns.filter_params, socket.assigns.page + 1, [])}
  end

  defp load(socket, filters, page, opts) do
    {rows, more?} = Finance.list_payments(socket.assigns.staff_scope, filters, page)

    socket
    |> assign(
      filters: to_form(filters, as: :payments),
      filter_params: filters,
      page: page,
      more?: more?
    )
    |> stream(:payments, rows, opts)
  end

  defp export_query(filters),
    do: filters |> Map.take(~w(from to)) |> Enum.reject(fn {_, v} -> v == "" end)
end
