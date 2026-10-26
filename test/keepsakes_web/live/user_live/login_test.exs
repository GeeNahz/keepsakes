defmodule KeepsakesWeb.UserLive.LoginTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures

  describe "login page" do
    test "renders the password form, the sign-in link button and the links", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/auth/log-in")

      assert has_element?(lv, "#login_form_password")
      assert has_element?(lv, "#login-submit")
      assert has_element?(lv, "#magic-link-submit")
      assert has_element?(lv, "#forgot-password-link")
      assert has_element?(lv, ~s(a[href="/auth/register"]))
    end
  end

  describe "user login - magic link" do
    test "sends magic link email when user exists", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/auth/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_password", user: %{email: user.email})
        |> render_submit(%{user: %{magic: "true"}})
        |> follow_redirect(conn, ~p"/auth/log-in")

      assert html =~ "If your email is in our system"

      assert Keepsakes.Repo.get_by!(Keepsakes.Accounts.UserToken, user_id: user.id).context ==
               "login"
    end

    test "does not disclose if user is registered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/auth/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_password", user: %{email: "idonotexist@example.com"})
        |> render_submit(%{user: %{magic: "true"}})
        |> follow_redirect(conn, ~p"/auth/log-in")

      assert html =~ "If your email is in our system"
    end
  end

  describe "user login - password" do
    test "redirects if user logs in with valid credentials", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/auth/log-in")

      form =
        form(lv, "#login_form_password",
          user: %{email: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/app/albums"
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/auth/log-in")

      form =
        form(lv, "#login_form_password", user: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/auth/log-in"
    end
  end

  describe "login navigation" do
    test "goes to registration from the Create an account link", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/auth/log-in")

      {:ok, register_lv, _html} =
        lv
        |> element(~s(a[href="/auth/register"]))
        |> render_click()
        |> follow_redirect(conn, ~p"/auth/register")

      assert has_element?(register_lv, "#registration_form")
    end

    test "goes to the reset page from Forgot password?", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/auth/log-in")

      {:ok, reset_lv, _html} =
        lv
        |> element("#forgot-password-link")
        |> render_click()
        |> follow_redirect(conn, ~p"/auth/reset-password")

      assert has_element?(reset_lv, "#reset_password_form")
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows login page with email filled in and read-only", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/auth/log-in")

      assert has_element?(
               lv,
               ~s(#login_form_password input[type="email"][readonly][value="#{user.email}"])
             )

      refute has_element?(lv, ~s(a[href="/auth/register"]))
    end
  end
end
