defmodule KeepsakesWeb.GuestLive.Access do
  @moduledoc """
  `/a/:slug`: the guest Access page. The code form posts to
  `KeepsakesWeb.GuestAccessController` (rate limited there); guests who
  already unlocked the link, and the owner, go straight to the album.
  Unknown, turned-off and expired links get a gentle "not available" page.
  Drawn by the album's template renderer.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Sharing
  alias KeepsakesWeb.GuestAccess

  @impl true
  def render(%{access: access, renderer: renderer} = assigns)
      when access in [:missing, :expired],
      do: renderer.unavailable(assigns)

  def render(%{renderer: renderer} = assigns), do: renderer.access(assigns)

  @impl true
  def mount(_params, _session, socket) do
    %{access: access, link: link, base_path: base} = socket.assigns

    case access do
      access when access in [:owner, :guest] ->
        # A returning guest counts as a visit; the owner peeking doesn't
        if access == :guest and not connected?(socket), do: Sharing.record_open(link)
        {:ok, push_navigate(socket, to: GuestAccess.start_path(base, link))}

      _ ->
        {:ok,
         assign(socket,
           page_title: (socket.assigns.album && socket.assigns.album.name) || "Keepsake"
         )}
    end
  end
end
