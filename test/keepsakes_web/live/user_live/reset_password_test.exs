defmodule KeepsakesWeb.UserLive.ResetPasswordTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Keepsakes.AccountsFixtures

  test "sends a reset link to a registered email", %{conn: conn} do
    user = user_fixture()
    # the fixture's own confirmation email
    assert_email_sent(subject: "Confirm your Keepsake account")
    {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

    lv |> form("#reset_password_form", user: %{email: user.email}) |> render_submit()

    assert has_element?(lv, "#reset-sent")

    assert_email_sent(fn email ->
      assert email.subject == "Reset your Keepsake password"
      assert email.text_body =~ "reset=1"
    end)
  end

  test "shows the same confirmation for unknown emails", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

    lv |> form("#reset_password_form", user: %{email: "nobody@example.com"}) |> render_submit()

    assert has_element?(lv, "#reset-sent")
    assert_no_email_sent()
  end
end
