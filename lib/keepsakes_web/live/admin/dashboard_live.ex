defmodule KeepsakesWeb.Admin.DashboardLive do
  @moduledoc """
  `admin.<host>/`: the platform at a glance (`Keepsakes.Metrics`).
  Every staff member lands here; without `dashboard.view` it's just a
  welcome pointing at the sections they can open.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.AdminComponents

  alias Keepsakes.Billing.Price
  alias Keepsakes.Metrics
  alias Keepsakes.Staff.Scope, as: StaffScope

  @impl true
  def render(%{metrics: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:dashboard}>
      <.header>
        Welcome, {@staff_scope.user.first_name}
        <:subtitle>Your sections are in the menu.</:subtitle>
      </.header>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:dashboard}>
      <.header>
        Dashboard
        <:subtitle>Customers only; staff accounts aren't counted.</:subtitle>
      </.header>

      <div id="dashboard-stats" class="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <.stat
          id="stat-customers"
          label="Customers"
          value={count(@metrics.customers)}
          note={"+#{count(@metrics.new_7d)} in 7 days · +#{count(@metrics.new_30d)} in 30"}
          navigate={if(@customers?, do: ~p"/customers")}
        />
        <.stat
          id="stat-trials"
          label="On the free trial"
          value={count(@metrics.trials)}
          navigate={if(@customers?, do: ~p"/customers?status=trialing")}
        />
        <.stat
          id="stat-paying"
          label="Paying"
          value={count(@metrics.paying)}
          note={"#{percent(@metrics.ever_paid, @metrics.customers)} of customers have ever paid"}
        />
        <.stat
          id="stat-churn"
          label="Churn, 30 days"
          value={if(@metrics.churn_rate, do: percent(@metrics.churn_rate), else: "–")}
          note={"#{count(@metrics.churned_30d)} moved from paid to free"}
        />
        <.stat
          :for={{currency, mrr} <- mrr_rows(@metrics.mrr)}
          id={"stat-mrr-#{String.downcase(currency)}"}
          label={"MRR · #{currency}"}
          value={Price.format(currency, mrr)}
          note={"#{Price.format(currency, mrr * 12)} a year · list prices"}
        />
        <.stat
          id="stat-storage"
          label="Photo storage"
          value={Keepsakes.Format.bytes(@metrics.storage_bytes)}
        />
        <.stat id="stat-tickets" label="Open tickets" value={count(@metrics.open_tickets)} />
      </div>

      <div class="mt-6 grid gap-4 xl:grid-cols-2">
        <.bar_chart
          id="signups-chart"
          title="Sign-ups per day"
          points={@metrics.signups_per_day}
          unit="sign-ups"
        />
        <.bar_chart
          id="uploads-chart"
          title="Photos uploaded per day"
          points={@metrics.uploads_per_day}
          unit="photos"
        />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.staff_scope

    metrics =
      if StaffScope.can?(scope, "dashboard.view"), do: Metrics.dashboard(scope), else: nil

    {:ok,
     assign(socket,
       page_title: "Dashboard",
       metrics: metrics,
       # Tiles link to the customer list for staff who can open it
       customers?: StaffScope.can?(scope, "users.view")
     )}
  end

  # NGN first, then USD, showing both even at zero
  defp mrr_rows(mrr), do: for(c <- ["NGN", "USD"], do: {c, Map.get(mrr, c, 0)})

  defp count(n), do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+$)/, ",")

  defp percent(_part, 0), do: "0%"
  defp percent(part, whole), do: percent(part / whole)
  defp percent(rate), do: "#{round(rate * 100)}%"
end
