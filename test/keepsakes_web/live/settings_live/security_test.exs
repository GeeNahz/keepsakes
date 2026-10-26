defmodule KeepsakesWeb.SettingsLive.SecurityTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures

  alias Keepsakes.Accounts
  alias Keepsakes.Accounts.TwoStep

  setup :register_and_log_in_user

  defp current_code(secret), do: NimbleTOTP.verification_code(secret)

  test "turning on two-step login shows recovery codes once", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/app/settings/security")

    lv |> element("#two-step-start") |> render_click()
    assert has_element?(lv, "#two-step-qr svg")

    # The secret behind the QR code, read back from the manual key
    key =
      lv |> element("#two-step-key") |> render() |> LazyHTML.from_fragment() |> LazyHTML.text()

    secret = key |> String.replace(" ", "") |> Base.decode32!(padding: false)

    lv |> form("#two-step-enable-form", code: "000000") |> render_submit()
    assert render(lv) =~ "didn&#39;t match"

    lv |> form("#two-step-enable-form", code: current_code(secret)) |> render_submit()
    assert has_element?(lv, "#recovery-codes")
    assert TwoStep.enabled?(Accounts.get_user!(user.id))

    lv |> element("#recovery-codes-done") |> render_click()
    assert has_element?(lv, "#two-step-on", "10 recovery codes left")
  end

  test "turning it off needs a code", %{conn: conn, user: user} do
    secret = TwoStep.new_secret()
    {:ok, _user, _codes} = TwoStep.enable(user, secret, current_code(secret))

    {:ok, lv, _html} = live(conn, ~p"/app/settings/security")
    lv |> form("#two-step-manage-form", code: "000000") |> render_submit(%{do: "disable"})
    assert TwoStep.enabled?(Accounts.get_user!(user.id))

    lv
    |> form("#two-step-manage-form", code: current_code(secret))
    |> render_submit(%{do: "disable"})

    refute TwoStep.enabled?(Accounts.get_user!(user.id))
  end

  test "lists devices and signs the others out", %{conn: conn, user: user} do
    other =
      Accounts.generate_user_session_token(user, %{
        user_agent: "Mozilla/5.0 (iPhone) Safari/604.1",
        ip: "10.0.0.9"
      })

    {:ok, lv, _html} = live(conn, ~p"/app/settings/security")
    assert has_element?(lv, "#devices", "This device")
    assert has_element?(lv, "#devices", "Safari on iPhone")
    assert has_element?(lv, "#devices", "10.0.0.9")

    lv |> element("#sign-out-others") |> render_click()
    refute Accounts.get_user_by_session_token(other)
    refute has_element?(lv, "#devices", "Safari on iPhone")
  end

  test "recovery codes work once at login" do
    user = user_fixture()
    secret = TwoStep.new_secret()
    {:ok, user, [code | _]} = TwoStep.enable(user, secret, current_code(secret))

    assert {:ok, user} = TwoStep.verify(user, String.downcase(code))
    assert length(user.recovery_codes) == 9
    assert {:error, :invalid_code} = TwoStep.verify(user, code)
  end
end
