defmodule KeepsakesWeb.OperationsTest do
  @moduledoc "What the server runs on: health checks, the error dashboard, metrics."
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.StaffFixtures

  describe "/healthz" do
    test "answers ok on the main host and the admin host", %{conn: conn} do
      for conn <- [conn, admin_host(conn)] do
        conn = get(conn, "/healthz")
        assert response(conn, 200) == "ok"
        assert get_resp_header(conn, "cache-control") == ["no-store"]
      end
    end

    test "answers HEAD requests, and skips sessions", %{conn: conn} do
      conn = head(conn, "/healthz")
      assert conn.status == 200
      assert get_resp_header(conn, "set-cookie") == []
    end

    test "other paths are left alone" do
      conn = Plug.Test.conn(:get, "/healthzz")
      refute KeepsakesWeb.Healthz.call(conn, []).halted
    end
  end

  describe "admin Errors pages" do
    setup do
      {:ok, stacktrace} =
        ErrorTracker.Stacktrace.new([
          {KeepsakesWeb.AlbumLive.Show, :mount, 3, [file: ~c"lib/keepsakes_web/x.ex", line: 12]}
        ])

      {:ok, error} = ErrorTracker.Error.new("RuntimeError", "boom\nmore detail", stacktrace)
      error = Keepsakes.Repo.insert!(error)

      occurrence =
        Keepsakes.Repo.insert!(%ErrorTracker.Occurrence{
          error_id: error.id,
          reason: "boom",
          context: %{"request.path" => "/app/albums"},
          breadcrumbs: ["opened album"],
          stacktrace: stacktrace
        })

      %{error: error, occurrence: occurrence}
    end

    test "list them in the admin layout, with a sidebar link", %{conn: conn, error: error} do
      {:ok, view, _html} = conn |> log_in_staff(staff_fixture()) |> live(~p"/errors")

      assert has_element?(view, "#admin-nav-errors")
      assert has_element?(view, "#error-#{error.id}", "RuntimeError")
      assert has_element?(view, "#error-#{error.id} td:nth-child(2)", "1")
    end

    test "filter by status and search", %{conn: conn, error: error} do
      {:ok, view, _html} = conn |> log_in_staff(staff_fixture()) |> live(~p"/errors")

      view |> form("#error-filters", errors: %{status: "resolved", search: ""}) |> render_change()
      refute has_element?(view, "#error-#{error.id}")

      view |> form("#error-filters", errors: %{status: "all", search: "boom"}) |> render_change()
      assert has_element?(view, "#error-#{error.id}")

      view
      |> form("#error-filters", errors: %{status: "all", search: "nothing"})
      |> render_change()

      refute has_element?(view, "#error-#{error.id}")
    end

    test "show one with its stack trace and context, and resolve it", %{
      conn: conn,
      error: error,
      occurrence: occurrence
    } do
      {:ok, view, _html} = conn |> log_in_staff(staff_fixture()) |> live(~p"/errors/#{error.id}")

      assert has_element?(view, "#admin-nav-errors")
      assert has_element?(view, "#error-reason", "more detail")
      assert has_element?(view, "#occurrence-#{occurrence.id}")
      assert has_element?(view, "#stacktrace", "KeepsakesWeb.AlbumLive.Show.mount/3")
      assert has_element?(view, "#occurrence-context", "/app/albums")

      view |> element("#error-resolve") |> render_click()
      assert has_element?(view, "#error-reopen")
      assert Keepsakes.Repo.reload!(error).status == :resolved

      view |> element("#error-mute") |> render_click()
      assert Keepsakes.Repo.reload!(error).muted

      actions = Keepsakes.Repo.all(Keepsakes.Audit.Event) |> Enum.map(& &1.action)
      assert "error.resolved" in actions
      assert "error.muted" in actions
    end

    test "errors.view alone can look but not change anything", %{conn: conn, error: error} do
      {:ok, role} =
        Keepsakes.Staff.create_role(staff_scope_fixture(), %{
          "name" => "Error readers",
          "permissions" => ["errors.view"]
        })

      {:ok, view, _html} =
        conn |> log_in_staff(staff_fixture([role.key])) |> live(~p"/errors/#{error.id}")

      refute has_element?(view, "#error-resolve")
      refute has_element?(view, "#error-mute")

      assert_raise Keepsakes.Staff.Forbidden, fn ->
        Keepsakes.Errors.resolve(Keepsakes.Staff.scope_for(staff_fixture([role.key]), nil), error)
      end
    end

    test "staff without errors.view get a 403 and no link", %{conn: conn, error: error} do
      conn = log_in_staff(conn, staff_fixture(["finance"]))

      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#admin-nav-errors")

      assert_error_sent 403, fn -> get(conn, ~p"/errors") end
      assert_error_sent 403, fn -> get(conn, ~p"/errors/#{error.id}") end
    end

    test "aren't on the main site", %{conn: conn} do
      assert conn |> get("/errors") |> response(404)
    end
  end

  describe "the metrics listener" do
    # PromEx warns that it isn't running, which is the point here
    @tag :capture_log
    test "/metrics is unavailable while metrics are off, other paths are 404s" do
      # Tests never start Keepsakes.PromEx (METRICS_ENABLED is production-only)
      assert Keepsakes.PromEx.children() == []

      conn = KeepsakesWeb.MetricsEndpoint.call(Plug.Test.conn(:get, "/metrics"), [])
      assert conn.status == 503

      conn = KeepsakesWeb.MetricsEndpoint.call(Plug.Test.conn(:get, "/"), [])
      assert conn.status == 404
    end
  end
end
