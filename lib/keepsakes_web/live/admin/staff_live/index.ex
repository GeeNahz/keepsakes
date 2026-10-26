defmodule KeepsakesWeb.Admin.StaffLive.Index do
  @moduledoc """
  `admin.<host>/staff`: who can open the admin portal and with which
  roles. Staff are existing Keepsake accounts: adding someone by email
  gives that account a staff membership (or changes its roles); removing
  them ends staff access and leaves their customer account alone.
  Needs `roles.manage`.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Accounts.User
  alias Keepsakes.Staff
  alias Keepsakes.Staff.Scope, as: StaffScope

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:staff}>
      <.header>
        Staff
        <:subtitle>Keepsake accounts that can open the admin portal.</:subtitle>
        <:actions>
          <.button id="add-staff" variant="primary" phx-click="new">
            <.icon name="hero-plus" class="size-4" /> Add staff
          </.button>
        </:actions>
      </.header>

      <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
        <table class="table">
          <thead>
            <tr>
              <th>Person</th>
              <th>Roles</th>
              <th>Status</th>
              <th><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody id="staff" phx-update="stream">
            <tr :for={{id, m} <- @streams.staff} id={id}>
              <td>
                <div class="flex items-center gap-3">
                  <.avatar
                    name={User.full_name(m.user)}
                    src={Keepsakes.Accounts.avatar_url(m.user)}
                    class="size-9 text-xs"
                  />
                  <div class="min-w-0">
                    <p class="truncate font-bold">{User.full_name(m.user)}</p>
                    <p class="truncate text-sm text-ks-muted">{m.user.email}</p>
                  </div>
                </div>
              </td>
              <td>
                <div class="flex flex-wrap gap-1.5">
                  <.badge
                    :for={role <- m.roles}
                    variant={if(role.system, do: "pending", else: "ready")}
                  >
                    {role.name}
                  </.badge>
                </div>
              </td>
              <td>
                <.badge :if={m.active} variant="ready">Active</.badge>
                <.badge :if={!m.active} variant="muted">Removed</.badge>
              </td>
              <td class="w-0">
                <div :if={!locked?(m, @staff_scope)} class="flex justify-end gap-2 whitespace-nowrap">
                  <.button id={"edit-staff-#{m.id}"} size="sm" phx-click="edit" phx-value-id={m.id}>
                    {if m.active, do: "Change roles", else: "Restore"}
                  </.button>
                  <%= cond do %>
                    <% !m.active or m.user_id == @staff_scope.user.id -> %>
                    <% @confirm_remove == m.id -> %>
                      <.button
                        id={"confirm-remove-staff-#{m.id}"}
                        size="sm"
                        variant="danger"
                        phx-click="remove"
                        phx-value-id={m.id}
                      >
                        Confirm remove
                      </.button>
                    <% true -> %>
                      <.button
                        id={"remove-staff-#{m.id}"}
                        size="sm"
                        phx-click="ask_remove"
                        phx-value-id={m.id}
                      >
                        Remove
                      </.button>
                  <% end %>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <.modal
        :if={@form}
        id="staff-dialog"
        show
        title={if(@editing, do: "Change roles", else: "Add staff")}
        subtitle="They sign in here with their existing Keepsake account."
        on_cancel={JS.push("close")}
      >
        <.form for={@form} id="staff-form" phx-submit="save" class="flex flex-col gap-3">
          <.input
            field={@form[:email]}
            type="email"
            label="Account email"
            placeholder="name@example.com"
            readonly={@editing}
            required
          />
          <fieldset class="flex flex-col gap-1">
            <legend class="mb-1.5 text-sm font-medium">Roles</legend>
            <label
              :for={role <- @roles}
              for={"staff-role-#{role.id}"}
              class={[
                "flex items-start gap-3 rounded-field border border-base-300 p-3",
                role.system && !@staff_scope.super_admin? && "opacity-50"
              ]}
            >
              <input
                type="checkbox"
                id={"staff-role-#{role.id}"}
                name="staff[role_ids][]"
                value={role.id}
                checked={role.id in @form[:role_ids].value}
                disabled={role.system && !@staff_scope.super_admin?}
                class="checkbox checkbox-primary checkbox-sm mt-0.5"
              />
              <span class="flex flex-col">
                <span class="font-medium">{role.name}</span>
                <span :if={role.description} class="text-sm text-ks-muted">{role.description}</span>
              </span>
            </label>
          </fieldset>
          <p :if={@error} id="staff-form-error" class="text-sm text-error">{@error}</p>
          <div class="flex justify-end gap-2.5 pt-1">
            <.button type="button" phx-click={JS.exec("data-cancel", to: "#staff-dialog")}>
              Cancel
            </.button>
            <.button id="staff-save" variant="primary" phx-disable-with="Saving…">Save</.button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Staff", roles: Staff.all_roles(), confirm_remove: nil)
     |> close_form()
     |> load()}
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply, open_form(socket, %{"email" => "", "role_ids" => []}, false)}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    m = find(socket, id)

    {:noreply,
     open_form(socket, %{"email" => m.user.email, "role_ids" => Enum.map(m.roles, & &1.id)}, true)}
  end

  def handle_event("close", _params, socket), do: {:noreply, close_form(socket)}

  def handle_event("save", %{"staff" => params}, socket) do
    email = params["email"] || ""
    role_ids = params["role_ids"] || []

    case Staff.grant(socket.assigns.staff_scope, email, role_ids) do
      {:ok, _membership} ->
        {:noreply,
         socket
         |> close_form()
         |> load()
         |> put_flash(:info, "Staff access saved for #{String.trim(email)}.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> open_form(%{"email" => email, "role_ids" => role_ids}, socket.assigns.editing)
         |> assign(:error, grant_error(reason))}
    end
  end

  def handle_event("ask_remove", %{"id" => id}, socket) do
    {:noreply, socket |> assign(:confirm_remove, id) |> load()}
  end

  def handle_event("remove", %{"id" => id}, socket) do
    socket = assign(socket, :confirm_remove, nil)

    case Staff.revoke(socket.assigns.staff_scope, find(socket, id)) do
      {:ok, m} ->
        {:noreply,
         socket
         |> load()
         |> put_flash(:info, "#{m.user.email} can no longer open the admin portal.")}

      {:error, :self} ->
        {:noreply, socket |> load() |> put_flash(:error, "You can't remove yourself.")}

      {:error, :last_super_admin} ->
        {:noreply, socket |> load() |> put_flash(:error, "Keep at least one Super Admin.")}

      {:error, :forbidden} ->
        {:noreply,
         socket |> load() |> put_flash(:error, "Only a Super Admin can remove a Super Admin.")}
    end
  end

  # Super Admins can only be changed by another Super Admin
  defp locked?(_m, %StaffScope{super_admin?: true}), do: false
  defp locked?(m, _scope), do: Enum.any?(m.roles, & &1.system)

  defp grant_error(:no_account),
    do: "There's no Keepsake account with that email. Ask them to sign up first."

  defp grant_error(:no_roles), do: "Pick at least one role."

  defp grant_error(:forbidden),
    do: "Only a Super Admin can give, change or take away Super Admin."

  defp open_form(socket, params, editing) do
    assign(socket, form: to_form(params, as: :staff), editing: editing, error: nil)
  end

  defp close_form(socket), do: assign(socket, form: nil, editing: false, error: nil)

  defp load(%{assigns: %{staff_scope: %StaffScope{} = scope}} = socket) do
    staff = Staff.list_staff(scope)

    socket
    |> assign(:staff_by_id, Map.new(staff, &{&1.id, &1}))
    |> stream(:staff, staff, reset: true)
  end

  defp find(socket, id), do: Map.fetch!(socket.assigns.staff_by_id, id)
end
