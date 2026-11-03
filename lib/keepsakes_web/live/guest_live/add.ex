defmodule KeepsakesWeb.GuestLive.Add do
  @moduledoc """
  `/a/:slug/add` (and `/:album/add` on customers' domains): guests who
  unlocked the link add photos for the owner to approve, when the owner
  turned guest uploads on. Drawn by the renderer's `add/1`.

  The guest gives their name and ticks that they may share the photos;
  optional details apply to every photo sent at once. Photos count toward
  the owner's plan straight away (`Keepsakes.Sharing.Engagement.add_photo/4`).
  """
  use KeepsakesWeb, :live_view

  on_mount {KeepsakesWeb.GuestAccess, :require_access}

  alias Keepsakes.{Albums, Entitlements}
  alias Keepsakes.Sharing.Engagement

  @accept ~w(.jpg .jpeg .png .heic .heif .webp)
  @max_entries 10
  @fields %{
    guest_name: :string,
    title: :string,
    month: :integer,
    year: :integer,
    caption: :string,
    rights: :boolean
  }

  @impl true
  def render(%{sealed?: true, renderer: renderer} = assigns), do: renderer.sealed(assigns)
  def render(%{renderer: renderer} = assigns), do: renderer.add(assigns)

  @impl true
  def mount(_params, _session, socket) do
    %{album: album, uploads?: uploads?, visitor_key: visitor_key} = socket.assigns

    if uploads? and is_binary(visitor_key) do
      max_upload_mb = Entitlements.max_upload_mb(Albums.owner_scope(album))

      {:ok,
       socket
       |> assign(
         page_title: "Add photos · #{album.name}",
         form: guest_form(%{}),
         added: 0,
         error: nil,
         max_upload_mb: max_upload_mb,
         max_entries: @max_entries
       )
       |> allow_upload(:photos,
         accept: @accept,
         max_entries: @max_entries,
         max_file_size: max_upload_mb * 1_000_000
       )}
    else
      {:ok, push_navigate(socket, to: socket.assigns.base_path <> "/timeline")}
    end
  end

  @impl true
  def handle_event("validate", %{"guest" => params}, socket),
    do: {:noreply, assign(socket, form: guest_form(params), error: nil)}

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_entry", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :photos, ref)}

  def handle_event("send", %{"guest" => params}, socket) do
    changeset = changeset(params)

    cond do
      Ecto.Changeset.get_field(changeset, :rights) != true ->
        {:noreply,
         assign(socket,
           form: guest_form(params),
           error: "Please confirm you may share these photos."
         )}

      blank?(Ecto.Changeset.get_field(changeset, :guest_name)) ->
        {:noreply, assign(socket, form: guest_form(params), error: "Please add your name.")}

      true ->
        send_photos(socket, Ecto.Changeset.apply_changes(changeset), params)
    end
  end

  defp send_photos(socket, details, params) do
    %{link: link, visitor_key: visitor_key} = socket.assigns

    results =
      consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
        upload = %{path: path, filename: entry.client_name, bytes: entry.client_size}
        {:ok, Engagement.add_photo(link, visitor_key, upload, details)}
      end)

    sent = Enum.count(results, &match?({:ok, _}, &1))

    error =
      case Enum.find(results, &match?({:error, _}, &1)) do
        nil -> nil
        {:error, reason} -> error_message(reason)
      end

    {:noreply,
     assign(socket,
       added: socket.assigns.added + sent,
       error: error,
       # Keep the name for the next batch; clear the per-batch details
       form: guest_form(%{"guest_name" => params["guest_name"], "rights" => params["rights"]})
     )}
  end

  defp error_message(:closed), do: "Adding photos isn't available right now."
  defp error_message(:name), do: "Please add your name."

  defp error_message({:rate_limited, _}),
    do: "That's a lot of photos at once. Please try again in an hour."

  defp error_message({:over_limit, _, _, _}), do: "This album can't take more photos right now."
  defp error_message(_), do: "Some photos couldn't be sent. Please try again."

  defp guest_form(params), do: params |> changeset() |> to_form(as: :guest)

  defp changeset(params) do
    {%{}, @fields}
    |> Ecto.Changeset.cast(params, Map.keys(@fields))
    |> Ecto.Changeset.validate_length(:guest_name, max: 60)
  end

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""
end
