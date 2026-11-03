defmodule KeepsakesWeb.GuestLive.Timeline do
  @moduledoc """
  `/a/:slug/timeline`: the guest memory timeline, drawn by the album's
  template renderer (`timeline/1`).

  `?auto=1` starts auto-scroll; the renderer's hook runs it. Memories still
  sealed by the time capsule arrive stripped (`Sharing.guest_view/2`) and
  are drawn as sealed polaroids; a sealed album shows `sealed/1` instead.
  With hearts on, each photo carries its count and whether this guest
  hearted it, updated live as anyone hearts.
  """
  use KeepsakesWeb, :live_view

  on_mount {KeepsakesWeb.GuestAccess, :require_access}

  alias Keepsakes.Sharing
  alias Keepsakes.Sharing.Engagement

  @impl true
  def render(%{sealed?: true, renderer: renderer} = assigns), do: renderer.sealed(assigns)
  def render(%{renderer: renderer} = assigns), do: renderer.timeline(assigns)

  @impl true
  def mount(params, _session, socket) do
    %{album: album, link: link, preview?: preview?} = socket.assigns
    now = DateTime.utc_now()
    memories = if socket.assigns.sealed?, do: [], else: Sharing.guest_view(album, now)

    {hearts, hearted} =
      if socket.assigns.reactions? do
        if connected?(socket), do: Engagement.subscribe(album)
        {Engagement.heart_counts(album), Engagement.hearted(album, socket.assigns.visitor_key)}
      else
        {%{}, MapSet.new()}
      end

    entries = entries(memories, hearts, hearted)

    {:ok,
     socket
     |> assign(
       page_title: album.name,
       memories: memories,
       now: now,
       auto?: params["auto"] == "1",
       hearts: hearts,
       hearted: hearted,
       # The unshared preview has no public link to download through
       downloads?: not preview? and Sharing.downloads_allowed?(link),
       last_side: entries |> List.last() |> then(&(&1 && &1.side)) || :left
     )
     |> stream(:entries, entries)}
  end

  @impl true
  def handle_event("heart", %{"id" => id}, socket) do
    %{link: link, visitor_key: key} = socket.assigns

    case key && Engagement.toggle_heart(link, key, id) do
      {:ok, hearted?, count} ->
        hearted =
          if hearted?,
            do: MapSet.put(socket.assigns.hearted, id),
            else: MapSet.delete(socket.assigns.hearted, id)

        {:noreply, socket |> assign(hearted: hearted) |> update_entry(id, count)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:hearts, memory_id, count}, socket),
    do: {:noreply, update_entry(socket, memory_id, count)}

  def handle_info(_message, socket), do: {:noreply, socket}

  # Re-renders one polaroid with its new heart count
  defp update_entry(socket, memory_id, count) do
    hearts = Map.put(socket.assigns.hearts, memory_id, count)
    socket = assign(socket, hearts: hearts)

    case Enum.find(
           entries(socket.assigns.memories, hearts, socket.assigns.hearted),
           &(&1.id == memory_id)
         ) do
      nil -> socket
      entry -> stream_insert(socket, :entries, entry)
    end
  end

  # Each entry knows its side and whether a new year starts here
  defp entries(memories, hearts, hearted) do
    memories
    |> Enum.with_index()
    |> Enum.map(fn {memory, index} ->
      previous = if index > 0, do: Enum.at(memories, index - 1)

      %{
        id: memory.id,
        memory: memory,
        index: index,
        side: if(rem(index, 2) == 0, do: :left, else: :right),
        year_chip: previous && previous.year != memory.year && memory.year,
        hearts: Map.get(hearts, memory.id, 0),
        hearted?: MapSet.member?(hearted, memory.id)
      }
    end)
  end
end
