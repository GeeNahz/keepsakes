defmodule KeepsakesWeb.GuestLive.Timeline do
  @moduledoc """
  `/a/:slug/timeline`: the guest memory timeline, drawn by the album's
  template renderer (`timeline/1`).

  `?auto=1` starts auto-scroll; the renderer's hook runs it.
  """
  use KeepsakesWeb, :live_view

  on_mount {KeepsakesWeb.GuestAccess, :require_access}

  alias Keepsakes.Sharing

  @impl true
  def render(%{renderer: renderer} = assigns), do: renderer.timeline(assigns)

  @impl true
  def mount(params, _session, socket) do
    %{album: album, link: link, preview?: preview?} = socket.assigns
    memories = Sharing.guest_memories(album)
    entries = entries(memories)

    {:ok,
     socket
     |> assign(
       page_title: album.name,
       memories: memories,
       auto?: params["auto"] == "1",
       # The unshared preview has no public link to download through
       downloads?: link.allow_downloads == true and not preview?,
       last_side: entries |> List.last() |> then(&(&1 && &1.side)) || :left
     )
     |> stream(:entries, entries)}
  end

  # Each entry knows its side and whether a new year starts here
  defp entries(memories) do
    memories
    |> Enum.with_index()
    |> Enum.map(fn {memory, index} ->
      previous = if index > 0, do: Enum.at(memories, index - 1)

      %{
        id: memory.id,
        memory: memory,
        index: index,
        side: if(rem(index, 2) == 0, do: :left, else: :right),
        year_chip: previous && previous.year != memory.year && memory.year
      }
    end)
  end
end
