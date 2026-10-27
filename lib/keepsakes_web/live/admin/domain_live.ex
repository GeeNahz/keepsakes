defmodule KeepsakesWeb.Admin.DomainLive do
  @moduledoc """
  `admin.<host>/domains`: every customer domain with its owner, status,
  last check and why it isn't connected; check again, block (with a
  reason; the site stops at once) or unblock; and the names nobody may
  use. Needs `domains.manage`.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Accounts.User
  alias Keepsakes.Domains.Admin
  alias Keepsakes.Staff.Scope, as: StaffScope

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:domains}>
      <.header>
        Domains
        <:subtitle>Customers' own web addresses for their public sites.</:subtitle>
      </.header>

      <.form
        for={@filters}
        id="domain-filters"
        phx-change="filter"
        class="mb-4 flex flex-wrap items-end gap-3"
      >
        <div class="w-full sm:w-64">
          <.input
            field={@filters[:q]}
            type="search"
            label="Search"
            placeholder="Domain or owner email"
            phx-debounce="300"
          />
        </div>
        <div class="w-40">
          <.input
            field={@filters[:status]}
            type="select"
            label="Status"
            prompt="Any"
            options={[
              {"Connected", "verified"},
              {"Waiting", "pending"},
              {"Not connected", "failed"},
              {"Blocked", "blocked"}
            ]}
          />
        </div>
      </.form>

      <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
        <table class="table">
          <thead>
            <tr>
              <th>Domain</th><th>Owner</th><th>Status</th><th>Last check</th><th>
                <span class="sr-only">Actions</span>
              </th>
            </tr>
          </thead>
          <tbody id="domains" phx-update="stream">
            <tr id="domains-empty" class="hidden only:table-row">
              <td colspan="5" class="py-10 text-center text-ks-muted">No domains.</td>
            </tr>
            <tr :for={{id, d} <- @streams.domains} id={id} class="align-top">
              <td>
                <p class="font-mono text-sm font-bold">{d.hostname}</p>
                <p :if={d.last_error && d.status != "verified"} class="max-w-72 text-xs text-ks-muted">
                  {d.last_error}
                </p>
                <p :if={d.blocked_reason} class="max-w-72 text-xs text-error">
                  Blocked: {d.blocked_reason}
                </p>
              </td>
              <td>
                <%!-- Staff accounts aren't customers, so they have no profile to open --%>
                <.link
                  :if={@customers? and d.user_id not in @staff_ids}
                  navigate={~p"/customers/#{d.user_id}"}
                  class="text-sm text-primary"
                >{d.user.email}</.link>
                <span :if={!@customers? or d.user_id in @staff_ids} class="text-sm">{d.user.email}</span>
                <p class="text-xs text-ks-muted">{User.full_name(d.user)}</p>
              </td>
              <td><.status status={d.status} /></td>
              <td class="whitespace-nowrap font-mono text-[13px]">
                {if d.last_checked_at,
                  do: Calendar.strftime(d.last_checked_at, "%d %b, %H:%M"),
                  else: "—"}
              </td>
              <td class="w-0">
                <div class="flex justify-end gap-2 whitespace-nowrap">
                  <.button
                    :if={d.status != "blocked"}
                    id={"check-domain-#{d.id}"}
                    size="sm"
                    phx-click="check"
                    phx-value-id={d.id}
                  >
                    Check now
                  </.button>
                  <.button
                    :if={d.status != "blocked"}
                    id={"block-domain-#{d.id}"}
                    size="sm"
                    variant="danger"
                    phx-click="ask_block"
                    phx-value-id={d.id}
                  >
                    Block
                  </.button>
                  <.button
                    :if={d.status == "blocked"}
                    id={"unblock-domain-#{d.id}"}
                    size="sm"
                    phx-click="unblock"
                    phx-value-id={d.id}
                  >
                    Unblock
                  </.button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <section
        id="blocked-names"
        class="mt-8 flex max-w-3xl flex-col gap-3 rounded-box border border-base-300 bg-base-100 p-5"
      >
        <div>
          <h2 class="font-bold">Blocked names</h2>
          <p class="text-sm text-ks-muted">
            Nobody can add these. Adding one also blocks domains that already match it.
          </p>
        </div>
        <ul :if={@blocked != []} class="flex flex-col divide-y divide-base-300">
          <li
            :for={b <- @blocked}
            id={"blocked-#{b.id}"}
            class="flex items-center justify-between gap-3 py-2"
          >
            <span>
              <span class="font-mono text-sm font-bold">{b.pattern}</span>
              <span class="text-sm text-ks-muted"> · {b.reason}</span>
            </span>
            <button
              type="button"
              id={"remove-blocked-#{b.id}"}
              phx-click="remove_blocked"
              phx-value-id={b.id}
              class="cursor-pointer text-sm font-bold text-primary"
            >
              Remove
            </button>
          </li>
        </ul>
        <.form
          for={@blocked_form}
          id="blocked-form"
          phx-submit="add_blocked"
          class="flex flex-wrap items-start gap-2"
        >
          <div class="w-56">
            <.input
              field={@blocked_form[:pattern]}
              placeholder="bad.example or *.bad.example"
              required
            />
          </div>
          <div class="w-64">
            <.input field={@blocked_form[:reason]} placeholder="Reason" required />
          </div>
          <.button id="add-blocked" variant="primary">Block name</.button>
        </.form>
      </section>

      <.modal
        :if={@blocking}
        id="block-dialog"
        show
        title={"Block #{@blocking.hostname}"}
        on_cancel={JS.push("close")}
      >
        <p class="text-sm text-ks-muted">
          Its site stops straight away. The customer can contact support.
        </p>
        <.form for={%{}} id="block-form" phx-submit="block" class="flex flex-col gap-3">
          <.input
            name="reason"
            id="block-reason"
            value=""
            label="Reason (staff and customer see it)"
            required
          />
          <div class="flex justify-end gap-2.5">
            <.button type="button" phx-click={JS.exec("data-cancel", to: "#block-dialog")}>Cancel</.button>
            <.button id="confirm-block" variant="danger">Block</.button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  attr :status, :string, required: true

  defp status(assigns) do
    ~H"""
    <%= case @status do %>
      <% "verified" -> %>
        <.badge variant="ready">Connected</.badge>
      <% "pending" -> %>
        <.badge variant="pending">Waiting</.badge>
      <% "failed" -> %>
        <.badge variant="muted">Not connected</.badge>
      <% "blocked" -> %>
        <span class="badge h-auto rounded-full border-0 bg-error/15 px-2.5 py-1 text-xs font-bold text-error">Blocked</span>
    <% end %>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Domains",
       customers?: StaffScope.can?(socket.assigns.staff_scope, "users.view"),
       filter_params: %{"q" => "", "status" => ""},
       blocking: nil
     )
     |> load()}
  end

  @impl true
  def handle_event("filter", %{"domains" => params}, socket) do
    {:noreply, socket |> assign(filter_params: Map.take(params, ~w(q status))) |> load()}
  end

  def handle_event("check", %{"id" => id}, socket) do
    scope = socket.assigns.staff_scope
    {:ok, d} = Admin.check(scope, Admin.get!(scope, id))

    {:noreply,
     socket |> load() |> put_flash(:info, "#{d.hostname}: #{d.last_error || "connected"}.")}
  end

  def handle_event("ask_block", %{"id" => id}, socket),
    do: {:noreply, assign(socket, blocking: Admin.get!(socket.assigns.staff_scope, id))}

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, blocking: nil)}

  def handle_event("block", %{"reason" => reason}, socket) do
    case Admin.block(socket.assigns.staff_scope, socket.assigns.blocking, reason) do
      {:ok, d} ->
        {:noreply,
         socket |> assign(blocking: nil) |> load() |> put_flash(:info, "Blocked #{d.hostname}.")}

      {:error, :reason_required} ->
        {:noreply, put_flash(socket, :error, "Add a reason.")}
    end
  end

  def handle_event("unblock", %{"id" => id}, socket) do
    scope = socket.assigns.staff_scope
    {:ok, d} = Admin.unblock(scope, Admin.get!(scope, id))

    {:noreply,
     socket
     |> load()
     |> put_flash(:info, "Unblocked #{d.hostname}; it's verified on its next good check.")}
  end

  def handle_event("add_blocked", %{"blocked_hostname" => params}, socket) do
    case Admin.add_blocked(socket.assigns.staff_scope, params) do
      {:ok, b} -> {:noreply, socket |> load() |> put_flash(:info, "Blocked #{b.pattern}.")}
      {:error, changeset} -> {:noreply, assign(socket, blocked_form: to_form(changeset))}
    end
  end

  def handle_event("remove_blocked", %{"id" => id}, socket) do
    scope = socket.assigns.staff_scope

    case Enum.find(socket.assigns.blocked, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      blocked ->
        {:ok, _} = Admin.remove_blocked(scope, blocked)
        {:noreply, load(socket)}
    end
  end

  defp load(socket) do
    scope = socket.assigns.staff_scope
    domains = Admin.list(scope, socket.assigns.filter_params)

    socket
    |> assign(
      blocked: Admin.list_blocked(scope),
      staff_ids: Keepsakes.Repo.all(Keepsakes.Staff.staff_user_ids_query()) |> MapSet.new(),
      filters: to_form(socket.assigns.filter_params, as: :domains),
      blocked_form: to_form(Admin.change_blocked())
    )
    |> stream(:domains, domains, reset: true)
  end
end
