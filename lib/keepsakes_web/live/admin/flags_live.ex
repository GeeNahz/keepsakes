defmodule KeepsakesWeb.Admin.FlagsLive do
  @moduledoc """
  `admin.<host>/flags`: feature flags declared in `Keepsakes.Flags`, each
  off, on for chosen customers, or on for everyone, with the chosen
  customers listed and added by email. Needs `flags.manage`.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Flags

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:flags}>
      <.header>
        Feature flags
        <:subtitle>Turn features on gradually: for a few customers first, then everyone.</:subtitle>
      </.header>

      <div class="flex max-w-3xl flex-col gap-4">
        <section
          :for={flag <- Flags.all()}
          id={"flag-#{flag.key}"}
          class="flex flex-col gap-3 rounded-box border border-base-300 bg-base-100 p-5"
        >
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="min-w-0 flex-1">
              <h2 class="font-bold">{flag.name}</h2>
              <p class="text-sm text-ks-muted">{flag.description}</p>
              <p class="font-mono text-xs text-ks-muted">{flag.key}</p>
            </div>
            <div class="join" role="radiogroup" aria-label={"#{flag.name} is on for"}>
              <button
                :for={
                  {label, value} <- [
                    {"Off", :off},
                    {"Chosen customers", :chosen},
                    {"Everyone", :everyone}
                  ]
                }
                id={"flag-#{flag.key}-#{value}"}
                type="button"
                role="radio"
                aria-checked={to_string(state(@states, flag.key) == value)}
                phx-click="set"
                phx-value-flag={flag.key}
                phx-value-to={value}
                class={[
                  "btn join-item btn-sm",
                  if(state(@states, flag.key) == value,
                    do: "btn-primary",
                    else: "btn-outline border-ks-field"
                  )
                ]}
              >
                {label}
              </button>
            </div>
          </div>

          <div
            :if={state(@states, flag.key) == :chosen}
            class="flex flex-col gap-2 border-t border-base-300 pt-3"
          >
            <ul :if={users(@states, flag.key) != []} class="flex flex-wrap gap-2">
              <li
                :for={user <- users(@states, flag.key)}
                id={"flag-#{flag.key}-user-#{user.id}"}
                class="flex items-center gap-1.5 rounded-full bg-base-200 py-1 pl-3 pr-1 text-sm"
              >
                {user.email}
                <button
                  type="button"
                  aria-label={"Remove #{user.email}"}
                  phx-click="remove"
                  phx-value-flag={flag.key}
                  phx-value-user={user.id}
                  class="flex size-6 cursor-pointer items-center justify-center rounded-full hover:bg-base-300"
                >
                  <.icon name="hero-x-mark" class="size-3.5" />
                </button>
              </li>
            </ul>
            <p :if={users(@states, flag.key) == []} class="text-sm text-ks-muted">
              Nobody yet, so it's off for everyone. Add customers by email.
            </p>
            <.form for={%{}} id={"flag-#{flag.key}-add"} phx-submit="add" class="flex flex-wrap gap-2">
              <input type="hidden" name="flag" value={flag.key} />
              <input
                type="email"
                name="email"
                placeholder="customer@example.com"
                required
                aria-label="Customer email"
                class="input input-sm h-9 w-64 border-ks-field bg-base-100"
              />
              <.button size="sm">Add</.button>
            </.form>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Feature flags", chosen_open: MapSet.new()) |> load()}
  end

  @impl true
  def handle_event("set", %{"flag" => flag, "to" => to}, socket) do
    key = flag_key(flag)
    to = Map.fetch!(%{"off" => :off, "chosen" => :chosen, "everyone" => :everyone}, to)
    :ok = Flags.set(socket.assigns.staff_scope, key, to)

    # "Chosen customers" with nobody chosen yet is still off for everyone, but
    # the page keeps it selected so the first customer can be added
    chosen_open =
      if to == :chosen,
        do: MapSet.put(socket.assigns.chosen_open, key),
        else: MapSet.delete(socket.assigns.chosen_open, key)

    {:noreply, socket |> assign(:chosen_open, chosen_open) |> load()}
  end

  def handle_event("add", %{"flag" => flag, "email" => email}, socket) do
    case Flags.add_customer(socket.assigns.staff_scope, flag_key(flag), email) do
      {:ok, user} ->
        {:noreply, socket |> load() |> put_flash(:info, "Turned on for #{user.email}.")}

      {:error, :no_account} ->
        {:noreply, put_flash(socket, :error, "There's no account with that email.")}
    end
  end

  def handle_event("remove", %{"flag" => flag, "user" => user_id}, socket) do
    key = flag_key(flag)
    user = Enum.find(users(socket.assigns.states, key), &(&1.id == user_id))
    :ok = Flags.remove_customer(socket.assigns.staff_scope, key, user)
    {:noreply, load(socket)}
  end

  defp load(socket) do
    states =
      Map.new(Flags.keys(), fn key ->
        case Flags.state(key) do
          {:off, users} ->
            {key, {if(key in socket.assigns.chosen_open, do: :chosen, else: :off), users}}

          state ->
            {key, state}
        end
      end)

    assign(socket, states: states)
  end

  # Only declared flags (never atoms made from what the browser sends)
  defp flag_key(flag), do: Enum.find(Flags.keys(), &(to_string(&1) == flag))

  defp state(states, key), do: states |> Map.fetch!(key) |> elem(0)
  defp users(states, key), do: states |> Map.fetch!(key) |> elem(1)
end
