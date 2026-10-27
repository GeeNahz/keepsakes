defmodule KeepsakesWeb.MaintenanceTest do
  # Not async: settings are cached in a shared ETS table
  use KeepsakesWeb.ConnCase, async: false

  import Keepsakes.AccountsFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.{Audit, Settings}
  alias Keepsakes.Settings.Admin, as: SettingsAdmin

  setup do
    on_exit(fn ->
      Settings.reset(:maintenance_mode)
      Settings.reset(:maintenance_message)
      Settings.reset(:trial_days)
    end)

    :ok
  end

  defp maintenance_on(message \\ "Upgrading the database") do
    {:ok, _} = Settings.put(:maintenance_mode, true)
    {:ok, _} = Settings.put(:maintenance_message, message)
  end

  describe "maintenance mode" do
    test "the main site shows the maintenance page", %{conn: conn} do
      maintenance_on()

      for path <- ["/", "/auth/log-in", "/app/albums", "/a/some-album"] do
        conn = get(conn, path)
        assert conn.status == 503
        assert conn.resp_body =~ "Upgrading the database"
        assert get_resp_header(conn, "retry-after") == ["600"]
      end
    end

    test "webhooks and the admin portal keep working", %{conn: conn} do
      maintenance_on()

      assert post(conn, "/webhooks/flutterwave", %{}).status != 503
      assert conn |> admin_host() |> get(~p"/log-in") |> Map.get(:status) == 200
    end

    test "staff get through with the bypass link, and see the banner", %{conn: conn} do
      maintenance_on()
      staff = staff_fixture()
      "http://" <> _ = url = KeepsakesWeb.Maintenance.bypass_url(staff)
      %URI{path: path, query: query} = URI.parse(url)

      conn = get(conn, path <> "?" <> query)
      assert redirected_to(conn) == "/"

      conn = conn |> recycle() |> get(~p"/")
      assert conn.status == 200
      assert html_response(conn, 200) =~ "id=\"maintenance-banner\""
    end

    test "a bad or non-staff token doesn't", %{conn: conn} do
      maintenance_on()
      customer = user_fixture()
      %URI{path: path, query: query} = URI.parse(KeepsakesWeb.Maintenance.bypass_url(customer))

      assert get(conn, path <> "?" <> query).status == 503
      assert get(conn, "/maintenance/bypass?token=nope").status == 503
    end

    test "off: nothing changes", %{conn: conn} do
      assert get(conn, ~p"/").status == 200
      refute get(conn, ~p"/").resp_body =~ "maintenance-banner"
    end
  end

  describe "system settings" do
    test "saves only what changed, audited, and resets" do
      admin = staff_scope_fixture()

      assert {:ok, [:trial_days]} =
               SettingsAdmin.save(admin, %{"trial_days" => "30", "grace_days" => "7"})

      assert Settings.get(:trial_days) == 30
      assert Settings.overridden?(:trial_days)

      assert [%{changes: %{"before" => 60, "after" => 30}}] =
               Audit.list(admin, %{"action" => "setting.changed"})

      assert {:error, %{trial_days: :invalid}} =
               SettingsAdmin.save(admin, %{"trial_days" => "soon"})

      assert Settings.get(:trial_days) == 30

      :ok = SettingsAdmin.reset(admin, :trial_days)
      assert Settings.get(:trial_days) == 60
      refute Settings.overridden?(:trial_days)
    end

    test "need config.manage" do
      assert_raise Keepsakes.Staff.Forbidden, fn ->
        SettingsAdmin.save(staff_scope_fixture(["support"]), %{"trial_days" => "1"})
      end
    end
  end
end
