defmodule Keepsakes.SettingsTest do
  use Keepsakes.DataCase, async: true

  alias Keepsakes.Settings

  test "returns defaults when nothing is stored" do
    assert Settings.get(:trial_days) == 60
    assert Settings.get(:grace_days) == 7
    assert Settings.get(:image_long_edge) == 2400
    assert Settings.get(:signups_open) == true
    assert Settings.get(:default_template) == "trail"
  end

  test "put/2 casts form strings and overrides the default" do
    assert {:ok, 30} = Settings.put("trial_days", "30")
    assert Settings.get(:trial_days) == 30

    assert {:ok, true} = Settings.put(:maintenance_mode, "true")
    assert Settings.get(:maintenance_mode) == true
  end

  test "put/2 upserts on the same key" do
    {:ok, _} = Settings.put(:grace_days, 3)
    {:ok, _} = Settings.put(:grace_days, 10)

    assert Settings.get(:grace_days) == 10
    assert Repo.aggregate(Settings.Setting, :count) == 1
  end

  test "put/2 rejects unknown keys and uncastable values" do
    assert {:error, :unknown_setting} = Settings.put("nope", "1")
    assert {:error, :invalid} = Settings.put(:trial_days, "sixty")
    assert Settings.get(:trial_days) == 60
  end

  test "reset/1 falls back to the default" do
    {:ok, _} = Settings.put(:trial_days, 14)
    :ok = Settings.reset(:trial_days)

    assert Settings.get(:trial_days) == 60
  end
end
