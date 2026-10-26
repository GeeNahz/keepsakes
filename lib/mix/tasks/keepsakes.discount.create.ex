defmodule Mix.Tasks.Keepsakes.Discount.Create do
  @shortdoc "Creates a discount code"

  @moduledoc """
  Creates a discount code customers can enter when choosing a plan.

      $ mix keepsakes.discount.create LAUNCH20 --percent 20 --duration once
      $ mix keepsakes.discount.create FAMILY --percent 15 --duration forever --plans plus,pro
      $ mix keepsakes.discount.create SPRING --percent 30 --duration repeating --months 3 \\
          --max 100 --expires 2027-03-31 --description "Spring campaign"

  Options:

    * `--percent` (required) - 1 to 100
    * `--duration` (required) - `once` (first payment), `repeating`
      (with `--months`) or `forever`
    * `--months` - how many months a `repeating` code lasts
    * `--max` - how many people can use it (default: no cap)
    * `--expires` - last day it can be used, `YYYY-MM-DD` (UTC, end of day)
    * `--plans` - comma-separated plan slugs (default: every paid plan)
    * `--description` - a note for staff

  In a release, call `Keepsakes.Billing.Discounts.create_code/1` with
  `bin/keepsakes eval` instead (see that module).
  """
  use Mix.Task

  @requirements ["app.start"]

  @switches [
    percent: :integer,
    duration: :string,
    months: :integer,
    max: :integer,
    expires: :string,
    plans: :string,
    description: :string
  ]

  @impl true
  def run(args) do
    case OptionParser.parse(args, strict: @switches) do
      {opts, [code], []} ->
        create(code, opts)

      _ ->
        Mix.raise(
          "Usage: mix keepsakes.discount.create CODE --percent N --duration once|repeating|forever"
        )
    end
  end

  defp create(code, opts) do
    attrs = %{
      code: code,
      percent_off: opts[:percent],
      duration: opts[:duration],
      duration_months: opts[:months],
      max_redemptions: opts[:max],
      expires_at: expires_at(opts[:expires]),
      plan_slugs: plans(opts[:plans]),
      description: opts[:description]
    }

    case Keepsakes.Billing.Discounts.create_code(attrs) do
      {:ok, discount} ->
        Mix.shell().info(
          "Created #{discount.code}: #{Keepsakes.Billing.DiscountCode.summary(discount)}"
        )

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {message, values} ->
            Enum.reduce(values, message, fn {key, value}, acc ->
              String.replace(acc, "%{#{key}}", to_string(value))
            end)
          end)

        Mix.raise("Could not create the code: #{inspect(errors)}")
    end
  end

  defp expires_at(nil), do: nil

  defp expires_at(date) do
    case Date.from_iso8601(date) do
      {:ok, date} -> DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
      {:error, _} -> Mix.raise("--expires must be YYYY-MM-DD")
    end
  end

  defp plans(nil), do: []
  defp plans(list), do: list |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
end
