defmodule KeepsakesWeb.GuestLive.Slideshow do
  @moduledoc """
  `/a/:slug/slideshow`: memories as a slideshow, drawn by the album's
  template renderer (`slideshow/1`). Every slide is rendered once and the
  renderer's hook plays them, so playback never waits on the server.

  Memories sealed by the time capsule are left out. With the link's
  `slideshow_music` on (and the owner's plan and flag allowing it), the
  album's track plays after the guest taps "Play with music".
  """
  use KeepsakesWeb, :live_view

  on_mount {KeepsakesWeb.GuestAccess, :require_access}

  alias Keepsakes.Albums.Memory
  alias Keepsakes.{Music, Sharing}

  @impl true
  def render(%{sealed?: true, renderer: renderer} = assigns), do: renderer.sealed(assigns)
  def render(%{renderer: renderer} = assigns), do: renderer.slideshow(assigns)

  @impl true
  def mount(_params, _session, socket) do
    %{album: album} = socket.assigns
    now = DateTime.utc_now()

    memories =
      if socket.assigns.sealed?,
        do: [],
        else: album |> Sharing.guest_memories() |> Enum.reject(&Memory.sealed?(&1, now))

    {:ok,
     assign(socket,
       page_title: "Slideshow · #{album.name}",
       memories: memories,
       music_url: music_url(socket.assigns)
     )}
  end

  defp music_url(%{link: %{slideshow_music: true, user: owner}, album: album})
       when is_map(owner) do
    with :ok <- Music.available?(Keepsakes.Accounts.Scope.for_user(owner)),
         %Music.Track{} = track <- Music.get_track(album) do
      Music.url(track)
    else
      _ -> nil
    end
  end

  defp music_url(_assigns), do: nil
end
