defmodule KeepsakesWeb.GuestLive.Guestbook do
  @moduledoc """
  `/a/:slug/guestbook` (and `/:album/guestbook` on customers' domains):
  approved notes and a form to sign, when the owner turned hearts and the
  guestbook on. A guest's own note shows straight away, marked as waiting
  for approval; everyone else sees it once the owner or an editor
  approves it. Drawn by the renderer's `guestbook/1`.
  """
  use KeepsakesWeb, :live_view

  on_mount {KeepsakesWeb.GuestAccess, :require_access}

  alias Keepsakes.Sharing.Engagement

  @impl true
  def render(%{sealed?: true, renderer: renderer} = assigns), do: renderer.sealed(assigns)
  def render(%{renderer: renderer} = assigns), do: renderer.guestbook(assigns)

  @impl true
  def mount(_params, _session, socket) do
    %{album: album, reactions?: reactions?, visitor_key: visitor_key} = socket.assigns

    if reactions? and is_binary(visitor_key) do
      if connected?(socket), do: Engagement.subscribe(album)

      {:ok,
       socket
       |> assign(page_title: "Guestbook · #{album.name}", form: to_form(Engagement.change_note()))
       |> load_notes()}
    else
      {:ok, push_navigate(socket, to: socket.assigns.base_path <> "/timeline")}
    end
  end

  @impl true
  def handle_event("validate", %{"guestbook_entry" => params}, socket) do
    form = params |> Engagement.change_note() |> Map.put(:action, :validate) |> to_form()
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("sign", %{"guestbook_entry" => params}, socket) do
    %{link: link, visitor_key: visitor_key} = socket.assigns

    case Engagement.sign(link, visitor_key, params) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Thank you! Your note will appear once it's approved.")
         |> assign(form: to_form(Engagement.change_note(%{"name" => params["name"]})))
         |> load_notes()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, {:rate_limited, _}} ->
        {:noreply,
         put_flash(socket, :error, "You've left a few notes already. Please try again later.")}

      {:error, :closed} ->
        {:noreply, put_flash(socket, :error, "The guestbook is closed.")}
    end
  end

  @impl true
  def handle_info({:guestbook_changed, _album_id}, socket), do: {:noreply, load_notes(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp load_notes(socket),
    do:
      assign(socket,
        notes: Engagement.guestbook(socket.assigns.album, socket.assigns.visitor_key)
      )
end
