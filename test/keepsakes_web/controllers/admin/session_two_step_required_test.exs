defmodule KeepsakesWeb.Admin.SessionTwoStepRequiredTest do
  # Not async: turns on :require_staff_two_step for the whole app
  use KeepsakesWeb.ConnCase, async: false

  import Keepsakes.StaffFixtures

  alias Keepsakes.Accounts.TwoStep

  setup do
    Application.put_env(:keepsakes, :require_staff_two_step, true)
    on_exit(fn -> Application.put_env(:keepsakes, :require_staff_two_step, false) end)
  end

  test "staff without two-step login set it up before getting in", %{conn: conn} do
    user = staff_fixture()

    conn =
      conn
      |> admin_host()
      |> post(~p"/log-in", %{
        "email" => user.email,
        "password" => Keepsakes.AccountsFixtures.valid_user_password()
      })

    assert redirected_to(conn) == ~p"/two-step/setup"
    refute get_session(conn, :staff_token)

    conn = conn |> recycle() |> admin_host() |> get(~p"/two-step/setup")
    assert html_response(conn, 200) =~ "Set up two-step login"
    secret = get_session(conn, :staff_totp_secret)

    bad = conn |> recycle() |> admin_host() |> post(~p"/two-step/setup", %{"code" => "000000"})
    assert html_response(bad, 200) =~ "didn&#39;t match"

    conn =
      conn
      |> recycle()
      |> admin_host()
      |> post(~p"/two-step/setup", %{"code" => NimbleTOTP.verification_code(secret)})

    assert html_response(conn, 200) =~ "Save your recovery codes"
    assert TwoStep.enabled?(Keepsakes.Accounts.get_user(user.id))

    conn = conn |> recycle() |> admin_host() |> post(~p"/two-step/finish")
    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :staff_token)
  end
end
