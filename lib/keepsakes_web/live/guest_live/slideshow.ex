defmodule KeepsakesWeb.GuestLive.Slideshow do
  @moduledoc """
  `/a/:slug/slideshow`: memories as a slideshow, drawn by the album's
  template renderer (`slideshow/1`). Every slide is rendered once and the
  renderer's hook plays them, so playback never waits on the server.
  """
  use KeepsakesWeb, :live_view

  on_mount {KeepsakesWeb.GuestAccess, :require_access}

  alias Keepsakes.Sharing

  @impl true
  def render(%{renderer: renderer} = assigns), do: renderer.slideshow(assigns)

  @impl true
  def mount(_params, _session, socket) do
    memories = Sharing.guest_memories(socket.assigns.album)

    {:ok,
     assign(socket, page_title: "Slideshow · #{socket.assigns.album.name}", memories: memories)}
  end
end
