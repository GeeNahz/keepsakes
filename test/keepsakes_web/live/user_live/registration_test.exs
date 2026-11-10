defmodule KeepsakesWeb.UserLive.RegistrationTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Keepsakes.AccountsFixtures

  alias Keepsakes.Accounts

  describe "Registration page" do
    test "renders the form with name, email and password", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/auth/register")

      assert has_element?(lv, "#registration_form")
      assert has_element?(lv, "#user_first_name")
      assert has_element?(lv, "#user_last_name")
      assert has_element?(lv, "#user_email")
      assert has_element?(lv, "#user_password")
      assert has_element?(lv, ~s(#registration_form a[href="/auth/log-in"]))
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/auth/register")
        |> follow_redirect(conn, ~p"/app/albums")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/auth/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces", "password" => "short"})

      assert result =~ "must have the @ sign and no spaces"
      assert result =~ "should be at least 12 character"
    end

    test "shows a closed notice when sign-ups are paused", %{conn: conn} do
      {:ok, _} = Keepsakes.Settings.put(:signups_open, false)

      {:ok, lv, _html} = live(conn, ~p"/auth/register")

      assert has_element?(lv, "#signups-closed")
      refute has_element?(lv, "#registration_form")
    end
  end

  describe "register user" do
    test "creates the account, emails a confirmation link and logs in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/auth/register")

      email = unique_user_email()
      attrs = valid_user_attributes(email: email, first_name: "Grace", last_name: "Hopper")
      form = form(lv, "#registration_form", user: attrs)
      render_submit(form)

      user = Accounts.get_user_by_email(email)
      assert Accounts.User.full_name(user) == "Grace Hopper"
      refute user.confirmed_at
      assert_email_sent(subject: "Confirm your Keepsake account", to: [{"Grace Hopper", email}])

      conn = follow_trigger_action(form, conn)
      assert redirected_to(conn) == ~p"/app/albums"
      assert get_session(conn, :user_token)
    end

    test "an invite link records who invited the new user", %{conn: conn} do
      inviter = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/auth/register?ref=#{inviter.referral_code}")

      email = unique_user_email()

      lv
      |> form("#registration_form", user: valid_user_attributes(email: email))
      |> render_submit()

      assert Accounts.get_user_by_email(email).referred_by_id == inviter.id
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/auth/register")

      user = user_fixture(%{email: "test@email.com"})

      result =
        lv
        |> form("#registration_form", user: valid_user_attributes(email: user.email))
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "registration navigation" do
    test "goes to the login page from the Log in link", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/auth/register")

      {:ok, login_lv, _html} =
        lv
        |> element(~s(#registration_form a[href="/auth/log-in"]))
        |> render_click()
        |> follow_redirect(conn, ~p"/auth/log-in")

      assert has_element?(login_lv, "#login_form_password")
    end
  end
end
