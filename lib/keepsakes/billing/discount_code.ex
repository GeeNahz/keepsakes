defmodule Keepsakes.Billing.DiscountCode do
  @moduledoc """
  A discount code: `percent_off` for the first payment (`once`), for
  `duration_months` (`repeating`) or for as long as the plan lasts
  (`forever`). Optional cap on how many people can use it, expiry, and
  plans it works for (`plan_slugs`, empty for every paid plan).
  """
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "discount_codes" do
    field :code, :string
    field :description, :string
    field :percent_off, :integer
    field :duration, :string
    field :duration_months, :integer
    field :max_redemptions, :integer
    field :redemptions_count, :integer, default: 0
    field :expires_at, :utc_datetime
    field :plan_slugs, {:array, :string}, default: []
    field :active, :boolean, default: true

    timestamps()
  end

  @doc "For the mix task now and the admin portal later."
  def changeset(code, attrs) do
    code
    |> cast(attrs, [
      :code,
      :description,
      :percent_off,
      :duration,
      :duration_months,
      :max_redemptions,
      :expires_at,
      :plan_slugs,
      :active
    ])
    |> update_change(:code, &normalize/1)
    |> validate_required([:code, :percent_off, :duration])
    |> validate_format(:code, ~r/\A[A-Z0-9_-]{3,32}\z/,
      message: "use 3-32 letters, numbers, dashes or underscores"
    )
    |> validate_number(:percent_off, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_inclusion(:duration, ~w(once repeating forever))
    |> validate_months()
    |> validate_number(:max_redemptions, greater_than: 0)
    |> unique_constraint(:code)
  end

  defp validate_months(changeset) do
    case get_field(changeset, :duration) do
      "repeating" ->
        changeset
        |> validate_required([:duration_months])
        |> validate_number(:duration_months, greater_than: 0)

      _ ->
        put_change(changeset, :duration_months, nil)
    end
  end

  @doc "How a code is typed doesn't matter: `\" launch20 \"` is `\"LAUNCH20\"`."
  def normalize(code) when is_binary(code), do: code |> String.trim() |> String.upcase()
  def normalize(code), do: code

  @doc "`\"20% off for 3 months\"`."
  def summary(%{percent_off: pct, duration: "once"}), do: "#{pct}% off your first payment"

  def summary(%{percent_off: pct, duration: "repeating", duration_months: 1}),
    do: "#{pct}% off for 1 month"

  def summary(%{percent_off: pct, duration: "repeating", duration_months: months}),
    do: "#{pct}% off for #{months} months"

  def summary(%{percent_off: pct, duration: "forever"}),
    do: "#{pct}% off for as long as you keep the plan"
end
