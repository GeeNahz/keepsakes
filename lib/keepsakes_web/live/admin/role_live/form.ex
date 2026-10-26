defmodule KeepsakesWeb.Admin.RoleLive.Form do
  @moduledoc """
  `admin.<host>/roles/new` and `/roles/:id`: a role's name, description
  and permissions (grouped by section). Saving changes everyone who holds
  it the next time a page loads. Super Admin can't be opened here.
  Needs `roles.manage`.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Staff
  alias Keepsakes.Staff.{Permissions, Role}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:roles}>
      <.link navigate={~p"/roles"} class="mb-4 flex w-fit items-center gap-1 text-sm text-ks-muted">
        <.icon name="hero-arrow-left" class="size-4" /> Roles
      </.link>
      <.header>
        {if @live_action == :new, do: "New role", else: @role.name}
        <:subtitle>Pick what people with this role can see and do.</:subtitle>
      </.header>

      <.form
        for={@form}
        id="role-form"
        phx-change="validate"
        phx-submit="save"
        class="flex max-w-3xl flex-col gap-6"
      >
        <div class="grid gap-x-4 sm:grid-cols-2">
          <.input field={@form[:name]} label="Name" maxlength="40" phx-debounce="300" required />
          <.input
            field={@form[:description]}
            label="Description"
            maxlength="160"
            placeholder="Optional"
            phx-debounce="300"
          />
        </div>

        <%!-- Sends an empty list when every box is cleared --%>
        <input type="hidden" name="role[permissions][]" value="" />
        <div id="role-permissions" class="grid gap-4 md:grid-cols-2">
          <fieldset
            :for={{group, perms} <- @groups}
            class="flex flex-col gap-2 rounded-box border border-base-300 bg-base-100 p-4"
          >
            <legend class="px-1 text-[13px] font-bold uppercase tracking-[0.06em] text-ks-muted">
              {group}
            </legend>
            <label
              :for={{key, label} <- perms}
              for={"perm-#{key}"}
              class="flex cursor-pointer items-start gap-3"
            >
              <input
                type="checkbox"
                id={"perm-#{key}"}
                name="role[permissions][]"
                value={key}
                checked={key in @selected}
                class="checkbox checkbox-primary checkbox-sm mt-0.5"
              />
              <span class="flex flex-col">
                <span class="text-[15px]">{label}</span>
                <span class="font-mono text-xs text-ks-muted">{key}</span>
              </span>
            </label>
          </fieldset>
        </div>

        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <%= cond do %>
              <% @live_action == :new -> %>
              <% @confirm_delete -> %>
                <span class="mr-2 text-sm text-ks-muted">
                  Staff who hold only this role lose access to its pages.
                </span>
                <.button id="confirm-delete-role" type="button" variant="danger" phx-click="delete">
                  Delete role
                </.button>
              <% true -> %>
                <.button id="delete-role" type="button" phx-click="ask_delete">Delete</.button>
            <% end %>
          </div>
          <div class="flex gap-2.5">
            <.button type="button" navigate={~p"/roles"}>Cancel</.button>
            <.button id="save-role" variant="primary" phx-disable-with="Saving…">Save role</.button>
          </div>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.staff_scope

    role =
      case socket.assigns.live_action do
        :new -> %Role{}
        :edit -> Staff.get_role!(scope, params["id"])
      end

    # Super Admin is locked; there's nothing to edit
    if role.system do
      {:ok, push_navigate(socket, to: ~p"/roles")}
    else
      {:ok,
       socket
       |> assign(
         page_title: if(role.id, do: role.name, else: "New role"),
         role: role,
         groups: Permissions.grouped(),
         confirm_delete: false
       )
       |> assign_form(Staff.change_role(role))}
    end
  end

  @impl true
  def handle_event("validate", %{"role" => params}, socket) do
    changeset = Staff.change_role(socket.assigns.role, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"role" => params}, socket) do
    scope = socket.assigns.staff_scope

    result =
      case socket.assigns.live_action do
        :new -> Staff.create_role(scope, params)
        :edit -> Staff.update_role(scope, socket.assigns.role, params)
      end

    case result do
      {:ok, role} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved the #{role.name} role.")
         |> push_navigate(to: ~p"/roles")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("ask_delete", _params, socket),
    do: {:noreply, assign(socket, :confirm_delete, true)}

  def handle_event("delete", _params, socket) do
    {:ok, role} = Staff.delete_role(socket.assigns.staff_scope, socket.assigns.role)

    {:noreply,
     socket
     |> put_flash(:info, "Deleted the #{role.name} role.")
     |> push_navigate(to: ~p"/roles")}
  end

  defp assign_form(socket, changeset) do
    socket
    |> assign(:form, to_form(changeset))
    |> assign(:selected, Ecto.Changeset.get_field(changeset, :permissions) || [])
  end
end
