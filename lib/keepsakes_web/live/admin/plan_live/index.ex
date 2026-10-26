defmodule KeepsakesWeb.Admin.PlanLive.Index do
  @moduledoc """
  `admin.<host>/plans`: every plan in pricing-page order, whether new
  buyers can see it, how many people are on it and its current prices.
  Needs `plans.manage`.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Billing.{Admin, Price}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:plans}>
      <.header>
        Plans
        <:subtitle>
          What each plan includes and costs. Changes reach the pricing page right away.
        </:subtitle>
        <:actions>
          <.button id="new-plan" variant="primary" navigate={~p"/plans/new"}>
            <.icon name="hero-plus" class="size-4" /> New plan
          </.button>
        </:actions>
      </.header>

      <div id="plans" phx-update="stream" class="grid gap-4 lg:grid-cols-2">
        <article
          :for={{id, {plan, count}} <- @streams.plans}
          id={id}
          class="flex flex-col gap-3 rounded-box border border-base-300 bg-base-100 p-5"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="flex min-w-0 flex-col gap-1">
              <h2 class="flex flex-wrap items-center gap-2 text-lg font-bold">
                {plan.name}
                <.badge variant="muted">{kind_label(plan.kind)}</.badge>
                <.badge :if={!plan.public} variant="pending">Hidden</.badge>
              </h2>
              <p :if={plan.description} class="text-sm text-ks-muted">{plan.description}</p>
            </div>
            <.badge variant="muted" class="shrink-0">{people(count)}</.badge>
          </div>
          <ul :if={plan.prices != []} class="flex flex-wrap gap-2 text-sm">
            <li :for={price <- plan.prices} class="rounded-field bg-base-200 px-2.5 py-1 tabular-nums">
              {Price.format(price)} / {price.interval}
            </li>
          </ul>
          <p :if={plan.kind == "paid" and plan.prices == []} class="text-sm text-ks-amber-deep">
            No prices yet, so nobody can buy it.
          </p>
          <.link
            id={"edit-plan-#{plan.id}"}
            navigate={~p"/plans/#{plan.id}"}
            class="mt-auto w-fit text-sm font-bold text-primary"
          >
            Edit plan
          </.link>
        </article>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    plans = Admin.list_plans(socket.assigns.staff_scope)

    {:ok,
     socket
     |> assign(page_title: "Plans")
     |> stream_configure(:plans, dom_id: fn {plan, _count} -> "plans-#{plan.id}" end)
     |> stream(:plans, plans)}
  end

  defp kind_label("paid"), do: "Paid"
  defp kind_label("free"), do: "Free"
  defp kind_label("trial"), do: "Trial"

  defp people(1), do: "1 account"
  defp people(n), do: "#{n} accounts"
end
