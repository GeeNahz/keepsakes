defmodule Keepsakes.Billing.Price do
  @moduledoc "What a paid plan costs in one currency (NGN/USD) per month or year."
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "plan_prices" do
    field :currency, :string
    field :interval, :string
    # Kobo or cents
    field :amount_minor, :integer
    field :active, :boolean, default: true

    belongs_to :plan, Keepsakes.Billing.Plan

    timestamps()
  end

  @doc "`\"₦5,000\"` or `\"$12\"` (minor units dropped when whole)."
  def format(%__MODULE__{currency: currency, amount_minor: amount}), do: format(currency, amount)

  def format(currency, amount_minor) do
    symbol = if currency == "NGN", do: "₦", else: "$"
    major = div(amount_minor, 100)
    minor = rem(amount_minor, 100)
    whole = major |> Integer.to_string() |> group_thousands()

    if minor == 0,
      do: symbol <> whole,
      else: symbol <> whole <> "." <> String.pad_leading(Integer.to_string(minor), 2, "0")
  end

  defp group_thousands(digits) do
    digits
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end
end
