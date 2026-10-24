defmodule KeepsakesWeb.GuestComponents do
  @moduledoc """
  Pieces shared by the guest Timeline and Slideshow ("Trail" look):
  the owner-preview banner and memory text helpers. Stage 4 moves these
  behind the template renderer.
  """
  use KeepsakesWeb, :html

  alias Keepsakes.Albums.Memory
  alias Keepsakes.Storage

  # Guests may keep a page open for a while; links outlive a long visit
  @url_ttl 4 * 3600

  # The canvas tilt pattern, as literal classes so Tailwind generates them
  @tilts ~w(-rotate-3 rotate-[2.5deg] -rotate-[1.5deg] rotate-3 -rotate-[2.5deg] rotate-2)
  @tilt_degrees [-3, 2.5, -1.5, 3, -2.5, 2]

  @doc "Signed URL of a memory's photo at `width`, valid for a long visit."
  def photo_url(%Memory{} = memory, width),
    do: Storage.url(Memory.variant_key(memory, width), expires_in: @url_ttl)

  @doc "Tailwind rotate class for the polaroid at `index` (repeats the canvas pattern)."
  def tilt_class(index), do: Enum.at(@tilts, rem(index, length(@tilts)))

  @doc "The same tilt in degrees, for the slideshow hook."
  def tilt_degrees(index), do: Enum.at(@tilt_degrees, rem(index, length(@tilt_degrees)))

  @doc "`\"04 '19\"`, the stamp printed on a photo."
  def stamp(%Memory{month: m, year: y}),
    do:
      "#{String.pad_leading(Integer.to_string(m), 2, "0")} '#{rem(y, 100) |> Integer.to_string() |> String.pad_leading(2, "0")}"

  @doc "`\"Apr '19\"`, for slideshow stops."
  def short_stop(%Memory{month: m, year: y}),
    do:
      "#{Memory.month_names() |> Enum.at(m - 1) |> String.slice(0, 3)} '#{rem(y, 100) |> Integer.to_string() |> String.pad_leading(2, "0")}"

  @doc "`\"Ikeja, Lagos · with Mum & Dad\"`, or `nil`."
  def place_line(%Memory{place: place, people: people}) do
    with_people =
      case people do
        [] -> nil
        [one] -> "with #{one}"
        many -> "with #{many |> Enum.drop(-1) |> Enum.join(", ")} & #{List.last(many)}"
      end

    case Enum.reject([place, with_people], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  @doc "`\"APR 2019 · IKEJA\"`, the line inside a phone-size card."
  def card_line(%Memory{} = memory, show_details) do
    date = memory |> Memory.date_label() |> String.upcase() |> shorten_month()

    place =
      if show_details && memory.place,
        do: memory.place |> String.split(",") |> hd() |> String.trim() |> String.upcase()

    Enum.reject([date, place], &is_nil/1) |> Enum.join(" · ")
  end

  defp shorten_month(label) do
    case String.split(label, " ") do
      [month, year] -> "#{String.slice(month, 0, 3)} #{year}"
      _ -> label
    end
  end

  @doc "`\"6 MEMORIES · APR 2019 – DEC 2021\"`."
  def summary([]), do: "NO MEMORIES YET"

  def summary(memories) do
    count = if length(memories) == 1, do: "1 MEMORY", else: "#{length(memories)} MEMORIES"
    first = memories |> hd() |> Memory.short_date_label()
    last = memories |> List.last() |> Memory.short_date_label()
    range = if first == last, do: first, else: "#{first} – #{last}"
    String.upcase("#{count} · #{range}")
  end

  @doc "Banner shown when the owner looks at their own album as a guest."
  attr :album, :map, required: true
  attr :access, :atom, required: true
  attr :preview?, :boolean, default: false

  def owner_banner(assigns) do
    ~H"""
    <div
      :if={@access == :owner}
      id="owner-preview-banner"
      class="flex flex-wrap items-center justify-center gap-x-3 gap-y-1 bg-accent px-4 py-2 text-center text-sm font-medium text-accent-content"
    >
      <span>
        {if @preview?,
          do: "Preview: this is how guests will see your album.",
          else: "You're viewing your own album as a guest would."}
      </span>
      <.link navigate={~p"/albums/#{@album.slug}"} class="font-bold text-accent-content underline">
        Back to album
      </.link>
    </div>
    """
  end
end
