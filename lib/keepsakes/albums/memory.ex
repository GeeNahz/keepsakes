defmodule Keepsakes.Albums.Memory do
  @moduledoc """
  One photo in an album plus its story: title, month/year taken, caption,
  place and people.

  A memory starts as a `"draft"` while it sits on the upload screen and
  becomes `"published"` when the owner saves. Independently, `processing`
  tracks the media pipeline (`"pending"` → `"ready"` or `"failed"`).

  Stored files live under `storage_prefix`: `original` (deleted once
  processed) and the WebP variants from `variant_key/2`.
  """
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  @variants [480, 1200, 2400]
  @months ~w(January February March April May June July August September October November December)

  schema "memories" do
    field :status, :string, default: "draft"
    field :processing, :string, default: "pending"
    field :processing_error, :string
    field :title, :string
    field :month, :integer
    field :year, :integer
    field :caption, :string
    field :place, :string
    field :people, {:array, :string}, default: []
    field :position, :integer, default: 0
    field :storage_prefix, :string
    field :original_filename, :string
    field :original_bytes, :integer, default: 0
    field :stored_bytes, :integer, default: 0
    field :width, :integer
    field :height, :integer
    field :taken_on, :date

    belongs_to :album, Keepsakes.Albums.Album
    belongs_to :user, Keepsakes.Accounts.User

    # Microseconds keep photos uploaded in the same second in upload order
    timestamps(type: :utc_datetime_usec)
  end

  @doc "Fields the owner edits in the memory form."
  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [:title, :month, :year, :caption, :place])
    |> update_change(:title, &blank_to_nil/1)
    |> update_change(:caption, &blank_to_nil/1)
    |> update_change(:place, &blank_to_nil/1)
    |> validate_length(:title, max: 80)
    |> validate_length(:caption, max: 280)
    |> validate_length(:place, max: 120)
    |> validate_number(:month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:year,
      greater_than_or_equal_to: 1900,
      less_than_or_equal_to: Date.utc_today().year
    )
    |> check_constraint(:month, name: :month_range)
  end

  @doc "Replaces the people tags (trimmed, de-duplicated, at most 20)."
  def people_changeset(memory, people) do
    people =
      people
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq_by(&String.downcase/1)

    memory
    |> change(people: people)
    |> validate_length(:people, max: 20, message: "can tag at most 20 people")
    |> validate_change(:people, fn :people, list ->
      if Enum.any?(list, &(String.length(&1) > 40)),
        do: [people: "names can be at most 40 characters"],
        else: []
    end)
  end

  @doc "Has the name and date it needs to sit on the timeline."
  def ready?(%__MODULE__{title: title, month: month, year: year}),
    do: not is_nil(title) and not is_nil(month) and not is_nil(year)

  @doc "What's missing: `nil`, `\"name\"`, `\"date\"` or `\"name + date\"`."
  def missing(%__MODULE__{} = memory) do
    case {is_nil(memory.title), is_nil(memory.month) or is_nil(memory.year)} do
      {false, false} -> nil
      {true, false} -> "name"
      {false, true} -> "date"
      {true, true} -> "name + date"
    end
  end

  @doc "Stored widths, smallest first."
  def variants, do: @variants

  @doc "Storage key of the WebP variant for `width` (480, 1200 or 2400)."
  def variant_key(%__MODULE__{storage_prefix: prefix}, width) when width in @variants,
    do: "#{prefix}/w#{width}.webp"

  @doc "Storage key of the uploaded original (kept only until processed)."
  def original_key(%__MODULE__{storage_prefix: prefix}), do: "#{prefix}/original"

  @doc "Every key this memory may own, for deletion."
  def all_keys(%__MODULE__{} = memory),
    do: [original_key(memory) | Enum.map(@variants, &variant_key(memory, &1))]

  @doc "Month names in order."
  def month_names, do: @months

  @doc "`\"April 2019\"`, `\"2019\"` or `nil`."
  def date_label(%__MODULE__{month: m, year: y}) when is_integer(m) and is_integer(y),
    do: "#{Enum.at(@months, m - 1)} #{y}"

  def date_label(%__MODULE__{year: y}) when is_integer(y), do: Integer.to_string(y)
  def date_label(_), do: nil

  @doc "`\"Apr 2019\"`, for compact lists."
  def short_date_label(%__MODULE__{month: m, year: y}) when is_integer(m) and is_integer(y),
    do: "#{@months |> Enum.at(m - 1) |> String.slice(0, 3)} #{y}"

  def short_date_label(memory), do: date_label(memory)

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
