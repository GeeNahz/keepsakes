defmodule KeepsakesWeb.Admin.RoleLive.Index do
  @moduledoc """
  `admin.<host>/roles`: the roles staff can hold, how many people hold
  each and what they allow. Super Admin is locked (every permission).
  Needs `roles.manage`.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Staff

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:roles}>
      <.header>
        Roles
        <:subtitle>What each kind of staff member can see and do.</:subtitle>
        <:actions>
          <.button id="new-role" variant="primary" navigate={~p"/roles/new"}>
            <.icon name="hero-plus" class="size-4" /> New role
          </.button>
        </:actions>
      </.header>

      <div id="roles" phx-update="stream" class="grid gap-4 lg:grid-cols-2">
        <article
          :for={{id, role} <- @streams.roles}
          id={id}
          class="flex flex-col gap-3 rounded-box border border-base-300 bg-base-100 p-5"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="flex min-w-0 flex-col gap-1">
              <h2 class="flex items-center gap-2 text-lg font-bold">
                {role.name}
                <.icon :if={role.system} name="hero-lock-closed" class="size-4 text-ks-muted" />
              </h2>
              <p :if={role.description} class="text-sm text-ks-muted">{role.description}</p>
            </div>
            <.badge variant="muted" class="shrink-0">
              {people(Map.get(@counts, role.id, 0))}
            </.badge>
          </div>
          <p class="text-sm">
            <%= if role.system do %>
              Every permission, including ones added later.
            <% else %>
              {permission_summary(role.permissions)}
            <% end %>
          </p>
          <.link
            :if={!role.system}
            id={"edit-role-#{role.id}"}
            navigate={~p"/roles/#{role.id}"}
            class="mt-auto w-fit text-sm font-bold text-primary"
          >
            Edit role
          </.link>
        </article>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Roles", counts: Staff.role_member_counts())
     |> stream(:roles, Staff.list_roles(socket.assigns.staff_scope))}
  end

  defp people(1), do: "1 person"
  defp people(n), do: "#{n} people"

  defp permission_summary([]), do: "No permissions yet."

  defp permission_summary(perms) do
    labels =
      Map.new(for {_g, list} <- Keepsakes.Staff.Permissions.grouped(), {k, l} <- list, do: {k, l})

    perms |> Enum.map(&Map.get(labels, &1, &1)) |> Enum.join(" · ")
  end
end
