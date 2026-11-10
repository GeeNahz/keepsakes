defmodule KeepsakesWeb.Admin.FinanceLive.Index do
  @moduledoc """
  `admin.<host>/finance`: money in per currency this month and last,
  12 months of revenue, revenue by plan, refunds and failed payments.
  Revenue is successful payments minus refunds. Needs `finance.view`.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.AdminComponents

  alias Keepsakes.Billing.Price
  alias Keepsakes.Finance
  alias Keepsakes.Staff.Scope, as: StaffScope

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:finance}>
      <.header>
        Finance
        <:subtitle>Money in, after refunds. NGN and USD are kept apart.</:subtitle>
        <:actions>
          <.button id="all-payments" navigate={~p"/finance/payments"}>All payments</.button>
        </:actions>
      </.header>

      <.finance_tabs active={:overview} />

      <div id="finance-stats" class="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <.stat
          :for={{currency, net} <- @o.this_month}
          id={"stat-this-month-#{String.downcase(currency)}"}
          label={"This month · #{currency}"}
          value={Price.format(currency, net)}
          note={"Last month #{Price.format(currency, @o.last_month[currency])}"}
        />
        <.stat
          id="stat-refunds"
          label="Refunded this month"
          value={money_list(@o.refunds_this_month)}
        />
        <.stat
          id="stat-failed"
          label="Failed payments, 30 days"
          value={to_string(@o.failed_30d)}
          navigate={~p"/finance/payments?status=failed"}
        />
      </div>

      <div class="mt-6 grid gap-4 xl:grid-cols-2">
        <.bar_chart
          :for={{currency, months} <- @o.monthly}
          id={"revenue-#{String.downcase(currency)}"}
          title={"#{currency} revenue per month"}
          points={months}
          unit="revenue"
          period="month"
          format={&Price.format(currency, &1)}
        />
      </div>

      <section id="revenue-by-plan" class="mt-6 rounded-box border border-base-300 bg-base-100 p-5">
        <h2 class="mb-3 font-bold">This month by plan</h2>
        <p :if={@o.by_plan == []} class="text-sm text-ks-muted">No payments yet this month.</p>
        <table :if={@o.by_plan != []} class="table">
          <thead>
            <tr>
              <th>Plan</th><th>Currency</th><th class="text-right">Revenue</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{plan, currency, net} <- @o.by_plan}>
              <td>{plan}</td>
              <td>{currency}</td>
              <td class="text-right tabular-nums">{Price.format(currency, net)}</td>
            </tr>
          </tbody>
        </table>
      </section>

      <p :if={@export?} class="mt-6 text-sm text-ks-muted">
        CSV exports are on the
        <.link navigate={~p"/finance/payments"} class="font-bold text-primary">payments</.link>
        page.
      </p>
    </Layouts.app>
    """
  end

  attr :active, :atom, required: true

  def finance_tabs(assigns) do
    ~H"""
    <div role="tablist" class="tabs tabs-border mb-6">
      <.link
        role="tab"
        navigate={~p"/finance"}
        class={["tab", @active == :overview && "tab-active"]}
      >
        Overview
      </.link>
      <.link
        role="tab"
        navigate={~p"/finance/payments"}
        class={["tab", @active == :payments && "tab-active"]}
      >
        Payments
      </.link>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.staff_scope

    {:ok,
     assign(socket,
       page_title: "Finance",
       o: Finance.overview(scope),
       export?: StaffScope.can?(scope, "finance.export")
     )}
  end

  defp money_list(by_currency) do
    by_currency
    |> Enum.sort()
    |> Enum.map_join(" · ", fn {currency, minor} -> Price.format(currency, minor) end)
  end
end
