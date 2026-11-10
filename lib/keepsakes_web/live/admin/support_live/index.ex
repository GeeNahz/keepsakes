defmodule KeepsakesWeb.Admin.SupportLive.Index do
  @moduledoc """
  `admin.<host>/support`: the support inbox. Shows tickets needing a reply
  by default, unanswered ones first by when their first reply is due
  (SLA badge), with filters kept in the URL. Updates live as tickets come
  in or change. Needs `support.view`.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.SupportComponents, only: [when_text: 1]

  alias Keepsakes.Accounts.User
  alias Keepsakes.Support
  alias Keepsakes.Support.{Admin, Ticket}

  @filters ~w(view q status priority category assignee)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:support}>
      <.header>
        Support
        <:subtitle>Customer tickets and album reports.</:subtitle>
        <:actions>
          <.button id="canned-replies" navigate={~p"/support/replies"}>Canned replies</.button>
        </:actions>
      </.header>

      <div role="tablist" class="tabs tabs-border mb-4">
        <.link
          role="tab"
          patch={~p"/support?#{Map.put(@query, "view", "needs_reply")}"}
          class={["tab", @filter_params["view"] != "all" && "tab-active"]}
          id="view-needs-reply"
        >
          Needs a reply
        </.link>
        <.link
          role="tab"
          patch={~p"/support?#{Map.put(@query, "view", "all")}"}
          class={["tab", @filter_params["view"] == "all" && "tab-active"]}
          id="view-all"
        >
          All tickets
        </.link>
      </div>

      <.form
        for={@filters}
        id="ticket-filters"
        phx-change="filter"
        phx-submit="filter"
        class="mb-4 flex flex-wrap items-end gap-3"
      >
        <input type="hidden" name="tickets[view]" value={@filter_params["view"]} />
        <div class="w-full sm:w-64">
          <.input
            field={@filters[:q]}
            type="search"
            label="Search"
            placeholder="Number, subject or email"
            phx-debounce="300"
            autocomplete="off"
          />
        </div>
        <div :if={@filter_params["view"] == "all"} class="w-44">
          <.input
            field={@filters[:status]}
            type="select"
            label="Status"
            prompt="Any"
            options={statuses()}
          />
        </div>
        <div class="w-36">
          <.input
            field={@filters[:priority]}
            type="select"
            label="Priority"
            prompt="Any"
            options={Enum.map(Admin.priorities(), &{String.capitalize(&1), &1})}
          />
        </div>
        <div class="w-48">
          <.input
            field={@filters[:category]}
            type="select"
            label="Category"
            prompt="Any"
            options={Ticket.category_options()}
          />
        </div>
        <div class="w-40">
          <.input
            field={@filters[:assignee]}
            type="select"
            label="Assigned to"
            prompt="Anyone"
            options={[{"Me", "me"}, {"Nobody yet", "unassigned"}]}
          />
        </div>
      </.form>

      <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
        <table class="table">
          <thead>
            <tr>
              <th>Ticket</th>
              <th>From</th>
              <th>Status</th>
              <th>First reply</th>
              <th>Assigned</th>
            </tr>
          </thead>
          <tbody id="tickets" phx-update="stream">
            <tr id="tickets-empty" class="hidden only:table-row">
              <td colspan="5" class="py-10 text-center text-ks-muted">Nothing here. Nicely done.</td>
            </tr>
            <tr :for={{id, t} <- @streams.tickets} id={id} class="transition-colors hover:bg-base-200">
              <td class="max-w-sm">
                <.link
                  navigate={~p"/support/#{t.number}"}
                  class="block text-base-content no-underline"
                >
                  <span class="font-mono text-xs text-ks-muted">{t.number}</span>
                  <span class="block truncate font-bold">{t.subject}</span>
                </.link>
                <span class="text-xs text-ks-muted">
                  {category_label(t.category)} · {String.capitalize(t.priority)}
                </span>
              </td>
              <td class="max-w-56">
                <span class="block truncate text-[15px]">{from(t)}</span>
                <span class="font-mono text-xs text-ks-muted">{when_text(t.last_activity_at)}</span>
              </td>
              <td><.staff_status_badge status={t.status} /></td>
              <td><.sla_badge ticket={t} /></td>
              <td class="text-sm">{(t.assignee && t.assignee.first_name) || "—"}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@more?} class="mt-4 flex justify-center">
        <.button id="load-more-tickets" phx-click="more" phx-disable-with="Loading…">Load more</.button>
      </div>
    </Layouts.app>
    """
  end

  attr :status, :string, required: true

  @doc "A ticket's status from the staff side."
  def staff_status_badge(assigns) do
    ~H"""
    <.badge variant={
      case @status do
        s when s in ["open", "awaiting_staff"] -> "pending"
        "awaiting_user" -> "ready"
        _ -> "muted"
      end
    }>
      {staff_status(@status)}
    </.badge>
    """
  end

  attr :ticket, :map, required: true

  @doc "On track / Due soon / Overdue / Replied, with when it's due on hover."
  def sla_badge(assigns) do
    assigns = assign(assigns, state: Admin.sla(assigns.ticket), due: Admin.due_at(assigns.ticket))

    ~H"""
    <span title={"Due #{Calendar.strftime(@due, "%-d %b, %H:%M")} UTC"} class="whitespace-nowrap">
      <%= case @state do %>
        <% :overdue -> %>
          <span class="badge h-auto rounded-full border-0 bg-error/15 px-2.5 py-1 text-xs font-bold text-error">
            Overdue
          </span>
        <% :due_soon -> %>
          <.badge variant="pending">Due soon</.badge>
        <% :on_track -> %>
          <.badge variant="ready">On track</.badge>
        <% :replied -> %>
          <.badge variant="muted">Replied</.badge>
        <% :none -> %>
          <span class="text-ks-muted">—</span>
      <% end %>
    </span>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Support.subscribe_inbox()
    {:ok, assign(socket, page_title: "Support")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.new(@filters, &{&1, params[&1] || ""})
    filters = if filters["view"] == "", do: Map.put(filters, "view", "needs_reply"), else: filters
    {:noreply, load(socket, filters, 0, reset: true)}
  end

  @impl true
  def handle_event("filter", %{"tickets" => params}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/support?#{compact(Map.take(params, @filters))}", replace: true)}
  end

  def handle_event("more", _params, socket) do
    {:noreply, load(socket, socket.assigns.filter_params, socket.assigns.page + 1, [])}
  end

  # A ticket came in or changed: show the first pages again, in order
  @impl true
  def handle_info({:ticket_updated, _id}, socket) do
    {:noreply, load(socket, socket.assigns.filter_params, 0, reset: true)}
  end

  defp load(socket, filters, page, opts) do
    {tickets, more?} = Admin.list(socket.assigns.staff_scope, filters, page)

    socket
    |> assign(
      filters: to_form(filters, as: :tickets),
      filter_params: filters,
      query: compact(filters),
      page: page,
      more?: more?
    )
    |> stream(:tickets, tickets, opts)
  end

  defp compact(params), do: params |> Enum.reject(fn {_k, v} -> v in [nil, ""] end) |> Map.new()

  defp statuses do
    Enum.map(~w(open awaiting_staff awaiting_user resolved closed), &{staff_status(&1), &1})
  end

  @doc "Status from the staff side."
  def staff_status("open"), do: "New"
  def staff_status("awaiting_staff"), do: "Waiting on us"
  def staff_status("awaiting_user"), do: "Waiting on customer"
  def staff_status("resolved"), do: "Solved"
  def staff_status("closed"), do: "Closed"

  defp category_label(category) do
    case List.keyfind(Ticket.category_options(), category, 1) do
      {label, _} -> label
      nil -> category
    end
  end

  defp from(%Ticket{user: %User{} = user}), do: User.full_name(user) <> " · " <> user.email
  defp from(%Ticket{reporter_email: email}) when is_binary(email), do: "Guest · " <> email
  defp from(_ticket), do: "Guest"
end
