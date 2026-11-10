defmodule KeepsakesWeb.Admin.SessionControllerTest do
  use KeepsakesWeb.ConnCase, async: true

  import Keepsakes.AccountsFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.Accounts.TwoStep
  alias Keepsakes.Audit

  defp sign_in(conn, user) do
    conn
    |> admin_host()
    |> post(~p"/log-in", %{"email" => user.email, "password" => valid_user_password()})
  end

  describe "hosts" do
    test "the main site's pages 404 on the admin host", %{conn: conn} do
      conn = conn |> admin_host() |> get(~p"/auth/log-in")
      assert conn.status == 404
    end

    test "admin pages don't exist on the main host", %{conn: conn} do
      assert get(conn, ~p"/log-in").status == 404
      assert get(conn, ~p"/staff").status == 404
    end

    test "the admin portal's / is the dashboard, not the landing page", %{conn: conn} do
      assert conn |> admin_host() |> get(~p"/") |> redirected_to() == ~p"/log-in"
    end

    test "a customer session doesn't open the admin portal", %{conn: conn} do
      user = staff_fixture()
      conn = conn |> log_in_user(user) |> admin_host() |> get(~p"/")
      assert redirected_to(conn) == ~p"/log-in"
    end

    test "admin pages aren't indexed", %{conn: conn} do
      conn = conn |> admin_host() |> get(~p"/log-in")
      assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
    end
  end

  describe "sign in" do
    test "customers can't sign in", %{conn: conn} do
      user = user_fixture() |> set_password()
      conn = sign_in(conn, user)
      assert html_response(conn, 200) =~ "don&#39;t open the admin portal"
      refute get_session(conn, :staff_pending)
    end

    test "a wrong password is refused", %{conn: conn} do
      user = staff_fixture()

      conn =
        conn |> admin_host() |> post(~p"/log-in", %{"email" => user.email, "password" => "nope"})

      assert html_response(conn, 200) =~ "don&#39;t open the admin portal"
    end

    # Two-step login isn't required by default (REQUIRE_STAFF_TWO_STEP);
    # the required flow is in session_two_step_required_test.exs
    test "staff without two-step login go straight in", %{conn: conn} do
      conn = sign_in(conn, staff_fixture())
      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :staff_token)
      refute get_session(conn, :user_token)
    end

    test "staff with two-step login enter a code", %{conn: conn} do
      user = staff_fixture()
      secret = TwoStep.new_secret()
      {:ok, user, _codes} = TwoStep.enable(user, secret, NimbleTOTP.verification_code(secret))

      conn = sign_in(conn, user)
      assert redirected_to(conn) == ~p"/two-step"
      refute get_session(conn, :staff_token)

      bad = conn |> recycle() |> admin_host() |> post(~p"/two-step", %{"code" => "000000"})
      assert html_response(bad, 200) =~ "didn&#39;t work"

      conn =
        conn
        |> recycle()
        |> admin_host()
        |> post(~p"/two-step", %{"code" => NimbleTOTP.verification_code(secret)})

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :staff_token)

      scope = Keepsakes.Staff.scope_for(user)
      assert [%{action: "staff.signed_in"}] = Audit.list(scope, %{"action" => "staff.signed_in"})
    end

    test "the code steps need a password first", %{conn: conn} do
      assert conn |> admin_host() |> get(~p"/two-step") |> redirected_to() == ~p"/log-in"
      assert conn |> admin_host() |> get(~p"/two-step/setup") |> redirected_to() == ~p"/log-in"
    end
  end

  describe "sessions" do
    test "signing out ends the staff session", %{conn: conn} do
      conn = conn |> log_in_staff(staff_fixture()) |> delete(~p"/log-out")
      assert redirected_to(conn) == ~p"/log-in"
      refute get_session(conn, :staff_token)
    end

    test "an expired session sends you back to sign in", %{conn: conn} do
      user = staff_fixture()
      conn = log_in_staff(conn, user)
      token = get_session(conn, :staff_token)
      offset_user_token(token, -13, :hour)

      assert conn |> get(~p"/") |> redirected_to() == ~p"/log-in"
    end

    test "losing staff access ends it straight away", %{conn: conn} do
      admin = staff_scope_fixture()
      user = staff_fixture(["support"])
      conn = log_in_staff(conn, user)

      {:ok, _} = Keepsakes.Staff.revoke(admin, Keepsakes.Staff.get_membership(user))
      assert conn |> get(~p"/") |> redirected_to() == ~p"/log-in"
    end
  end
end
