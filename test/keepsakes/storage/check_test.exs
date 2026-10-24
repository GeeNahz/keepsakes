defmodule Keepsakes.Storage.CheckTest do
  use ExUnit.Case, async: true

  alias Keepsakes.Storage.Check

  test "every step passes against the configured local storage and cleans up" do
    assert {:ok, steps} = Check.run()

    assert Enum.map(steps, &elem(&1, 1)) == [:ok, :ok, :ok, :ok, :ok]
    assert [put | _] = Check.format(steps)
    assert put =~ "ok    put healthchecks/"

    root = Application.fetch_env!(:keepsakes, Keepsakes.Storage)[:root]
    assert Path.wildcard(Path.join(root, "healthchecks/*")) == []
  end

  test "describe/0 names the adapter without secrets" do
    assert Check.describe() =~ "local disk at"
  end
end
