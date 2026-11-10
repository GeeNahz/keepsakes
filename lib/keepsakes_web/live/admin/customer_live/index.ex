defmodule KeepsakesWeb.Admin.CustomerLive.Index do
  @moduledoc """
  `admin.<host>/customers`: every customer account (staff left out),
  newest first, with search by name or email and filters by plan and
  status (also taken from the URL, e.g. `?status=trialing` from the
  dashboard). 50 at a time. Needs `users.view`.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Accounts.User
  alias Keepsakes.{Billing, Customers}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:customers}>
      <.header>
        Customers
        <:subtitle>Every customer account. Staff accounts aren't listed.</:subtitle>
      </.header>

      <.form
        for={@filters}
        id="customer-filters"
        phx-change="filter"
        phx-submit="filter"
        class="mb-4 flex flex-wrap items-end gap-3"
      >
        <div class="w-full sm:w-72">
          <.input
            field={@filters[:q]}
            type="search"
            label="Search"
            placeholder="Name or email"
            phx-debounce="300"
            autocomplete="off"
          />
        </div>
        <div class="w-44">
          <.input
            field={@filters[:plan]}
            type="select"
            label="Plan"
            prompt="All plans"
            options={@plan_options}
          />
        </div>
        <div class="w-48">
          <.input
            field={@filters[:status]}
            type="select"
            label="Status"
            prompt="Any status"
            options={Customers.statuses()}
          />
        </div>
      </.form>

      <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
        <table class="table">
          <thead>
            <tr>
              <th>Customer</th>
              <th>Plan</th>
              <th class="text-right">Albums</th>
              <th class="text-right">Storage</th>
              <th>Joined</th>
            </tr>
          </thead>
          <tbody id="customers" phx-update="stream">
            <tr id="customers-empty" class="hidden only:table-row">
              <td colspan="5" class="py-10 text-center text-ks-muted">No customers match.</td>
            </tr>
            <tr
              :for={{id, row} <- @streams.customers}
              id={id}
              class="transition-colors hover:bg-base-200"
            >
              <td>
                <.link
                  navigate={~p"/customers/#{row.id}"}
                  class="flex items-center gap-3 text-base-content no-underline"
                >
                  <.avatar
                    name={User.full_name(row.user)}
                    src={Keepsakes.Accounts.avatar_url(row.user)}
                    class="size-9 text-xs"
                  />
                  <span class="min-w-0">
                    <span class="block truncate font-bold">{User.full_name(row.user)}</span>
                    <span class="block truncate text-sm text-ks-muted">{row.user.email}</span>
                  </span>
                </.link>
              </td>
              <td>
                <div class="flex flex-wrap items-center gap-1.5">
                  <span class="text-[15px]">{Billing.status_label(row.subscription)}</span>
                  <.badge :if={row.user.suspended_at} variant="pending">Suspended</.badge>
                  <.badge :if={row.user.deletion_requested_at} variant="muted">
                    Deletion pending
                  </.badge>
                </div>
              </td>
              <td class="text-right tabular-nums">{row.albums}</td>
              <td class="text-right tabular-nums">{Keepsakes.Format.bytes(row.storage_bytes)}</td>
              <td class="whitespace-nowrap font-mono text-[13px]">
                {Calendar.strftime(row.user.inserted_at, "%d %b %Y")}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@more?} class="mt-4 flex justify-center">
        <.button id="load-more-customers" phx-click="more" phx-disable-with="Loading…">
          Load more
        </.button>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Customers", plan_options: Customers.plan_options())}
  end

  # Filters live in the URL so dashboard links and the back button work
  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.new(~w(q plan status), &{&1, params[&1] || ""})
    {:noreply, load(socket, filters, 0, reset: true)}
  end

  @impl true
  def handle_event("filter", %{"customers" => params}, socket) do
    query = params |> Map.take(~w(q plan status)) |> Enum.reject(fn {_k, v} -> v == "" end)
    {:noreply, push_patch(socket, to: ~p"/customers?#{query}", replace: true)}
  end

  def handle_event("more", _params, socket) do
    {:noreply, load(socket, socket.assigns.filter_params, socket.assigns.page + 1, [])}
  end

  defp load(socket, filters, page, opts) do
    {rows, more?} = Customers.list(socket.assigns.staff_scope, filters, page)

    socket
    |> assign(
      filters: to_form(filters, as: :customers),
      filter_params: filters,
      page: page,
      more?: more?
    )
    |> stream(:customers, rows, opts)
  end
end
