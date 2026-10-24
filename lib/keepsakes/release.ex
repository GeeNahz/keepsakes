defmodule Keepsakes.Release do
  @moduledoc """
  Tasks run inside a release, where Mix isn't available:

      bin/keepsakes eval "Keepsakes.Release.storage_check()"
  """

  @app :keepsakes

  @doc """
  Runs `Keepsakes.Storage.Check` and prints each step with `print`.
  Returns `true` when every step passed.
  """
  @spec storage_check((String.t() -> any())) :: boolean()
  def storage_check(print \\ &IO.puts/1) do
    {:ok, _} = Application.ensure_all_started(@app)

    print.("Checking #{Keepsakes.Storage.Check.describe()}")
    {status, steps} = Keepsakes.Storage.Check.run()
    Enum.each(Keepsakes.Storage.Check.format(steps), print)
    print.(if status == :ok, do: "Storage OK", else: "Storage check FAILED")

    status == :ok
  end
end
