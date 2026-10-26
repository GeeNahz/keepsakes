defmodule Keepsakes.Sharing.ShareLink do
  @moduledoc """
  An album's public link (`/a/<slug>`) and its 6-digit access code.

  The code is encrypted at rest so the owner can see and copy it again.
  `code_version` is bumped whenever the code changes; guest sessions store
  the version they unlocked, so a new code locks out old guests.
  """
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  @views ~w(timeline autoscroll slideshow)
  @expiry_options ~w(never 7 30)

  schema "share_links" do
    field :slug, :string
    field :code, Keepsakes.Encrypted.Binary, redact: true
    field :code_origin, :string, default: "auto"
    field :code_version, :integer, default: 1
    field :expires_at, :utc_datetime
    field :default_view, :string, default: "timeline"
    field :show_details, :boolean, default: true
    field :allow_downloads, :boolean, default: false
    field :slideshow_music, :boolean, default: false
    field :open_count, :integer, default: 0
    field :last_opened_at, :utc_datetime
    # Visits since the last guest-activity email
    field :opens_since_digest, :integer, default: 0
    # "never" | "7" | "30", only for the settings form
    field :expires_in, :string, virtual: true

    belongs_to :album, Keepsakes.Albums.Album
    belongs_to :user, Keepsakes.Accounts.User

    timestamps()
  end

  @doc "Guest-facing settings from the Share page."
  def settings_changeset(link, attrs, now \\ DateTime.utc_now(:second)) do
    link
    |> cast(attrs, [:default_view, :show_details, :allow_downloads, :expires_in])
    |> validate_inclusion(:default_view, @views)
    |> validate_inclusion(:expires_in, @expiry_options)
    |> put_expiry(now)
  end

  defp put_expiry(changeset, now) do
    case get_change(changeset, :expires_in) do
      nil -> changeset
      "never" -> put_change(changeset, :expires_at, nil)
      days -> put_change(changeset, :expires_at, DateTime.add(now, String.to_integer(days), :day))
    end
  end

  @doc """
  Validates a code typed by the owner: exactly 6 digits, and not one a
  stranger would try first (all one digit, or a straight run).
  """
  @spec validate_code(String.t() | nil) :: :ok | {:error, String.t()}
  def validate_code(code) when is_binary(code) do
    cond do
      not Regex.match?(~r/\A\d{6}\z/, code) -> {:error, "Enter exactly 6 numbers."}
      guessable?(code) -> {:error, "That code is too easy to guess. Try something less obvious."}
      true -> :ok
    end
  end

  def validate_code(_), do: {:error, "Enter exactly 6 numbers."}

  defp guessable?(code) do
    digits = code |> String.graphemes() |> Enum.map(&String.to_integer/1)

    steps =
      digits
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> b - a end)
      |> Enum.uniq()

    steps in [[0], [1], [-1]]
  end

  @doc "Expired links stop working for guests (the owner can still manage them)."
  def expired?(%__MODULE__{expires_at: nil}, _now), do: false
  def expired?(%__MODULE__{expires_at: at}, now), do: DateTime.compare(now, at) != :lt

  @doc "Expiry choices for the settings form (value is days, or `\"never\"`)."
  def expiry_options,
    do: [{"Never", "never"}, {"In 7 days", "7"}, {"In 30 days", "30"}]

  def view_options do
    [
      {"Timeline – guest scrolls", "timeline"},
      {"Timeline – scrolls by itself", "autoscroll"},
      {"Slideshow", "slideshow"}
    ]
  end

  def views, do: @views
end
