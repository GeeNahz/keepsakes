defmodule KeepsakesWeb.OwnerShell do
  @moduledoc """
  `on_mount` hook for every owner-portal LiveView. It loads what the
  `:owner` shell in `Layouts.app` shows on every page (the album sidebar
  and the storage meter with the plan's limits) into an `@owner` assign, and handles the New
  album dialog's events so each LiveView doesn't have to:

    * `"new_album_validate"` / `"new_album_create"` (form `album[...]`)

  It subscribes to the owner's album events and refreshes `@owner` on
  `{:albums_changed, _}`. Memory events continue to the LiveView when it
  defines `handle_info/2`.

  Pass it through: `<Layouts.app flash={@flash} current_scope={@current_scope} owner={@owner}>`.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  alias Keepsakes.{Albums, Billing, Entitlements}

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: Albums.subscribe(socket.assigns.current_scope)

    socket =
      socket
      |> assign(:owner, load(socket.assigns.current_scope, nil))
      |> attach_hook(:owner_shell_events, :handle_event, &handle_event/3)
      |> attach_hook(:owner_shell_info, :handle_info, &handle_info/2)

    {:cont, socket}
  end

  @doc "Marks `album_id` as the open album in the sidebar."
  def put_current_album(socket, album_id),
    do: update(socket, :owner, &Map.put(&1, :current_album_id, album_id))

  @doc "Reloads the sidebar and storage meter."
  def refresh(socket) do
    assign(socket, :owner, load(socket.assigns.current_scope, socket.assigns.owner))
  end

  defp load(scope, previous) do
    albums = Albums.list_albums(scope)
    storage_used = Albums.storage_used(scope)
    subscription = Billing.get_subscription(scope)
    limits = Entitlements.all(scope)

    %{
      albums: albums,
      storage_used: storage_used,
      storage_limit: limits.storage_bytes,
      plan_label: Billing.status_label(subscription),
      album_limit: limits.max_albums,
      # Over a limit after a downgrade: nothing is removed, additions stop
      over_limit:
        Enum.filter(
          [storage_bytes: storage_used, max_albums: length(albums)],
          fn {key, used} -> over?(used, limits[key]) end
        ),
      current_album_id: previous && previous.current_album_id,
      new_album_form: (previous && previous.new_album_form) || new_album_form()
    }
  end

  defp over?(_used, :unlimited), do: false
  defp over?(used, limit), do: used > limit

  @doc "Whether the plan's album limit is reached (the New album dialog says so)."
  def album_limit_reached?(%{albums: albums, album_limit: limit}),
    do: limit != :unlimited and length(albums) >= limit

  defp new_album_form(changeset \\ Albums.change_album()), do: to_form(changeset, as: :album)

  defp handle_event("new_album_validate", %{"album" => params}, socket) do
    changeset = Albums.change_album(%Albums.Album{}, params) |> Map.put(:action, :validate)
    {:halt, update(socket, :owner, &%{&1 | new_album_form: new_album_form(changeset)})}
  end

  defp handle_event("new_album_create", %{"album" => params}, socket) do
    case Albums.create_album(socket.assigns.current_scope, params) do
      {:ok, album} ->
        socket =
          socket
          |> update(:owner, &%{&1 | new_album_form: new_album_form()})
          |> refresh()
          |> put_flash(:info, "“#{album.name}” is ready. Add your first memory.")
          |> push_navigate(to: "/app/albums/#{album.slug}")

        {:halt, socket}

      {:error, {:over_limit, _, _, _}} ->
        # The dialog switches to its upgrade notice
        {:halt, refresh(socket)}

      {:error, changeset} ->
        {:halt, update(socket, :owner, &%{&1 | new_album_form: new_album_form(changeset)})}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp handle_info({:albums_changed, _user_id}, socket), do: {:halt, refresh(socket)}

  # Anything that changes counts or storage also sends :albums_changed, so
  # memory events only matter to LiveViews that handle them
  defp handle_info(message, socket)
       when elem(message, 0) in [:memory_updated, :memory_deleted] do
    if function_exported?(socket.view, :handle_info, 2),
      do: {:cont, socket},
      else: {:halt, socket}
  end

  defp handle_info(_message, socket), do: {:cont, socket}
end
