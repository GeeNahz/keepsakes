defmodule KeepsakesWeb.TermsAndPwaTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures

  alias Keepsakes.Accounts

  describe "terms of use" do
    test "the page renders with the rights section", %{conn: conn} do
      html = conn |> get(~p"/terms") |> html_response(200)
      assert html =~ ~s(id="terms-uploads")
      assert html =~ Accounts.terms_version()
    end

    test "sign-up needs the agreement and records it" do
      attrs = valid_user_attributes() |> Map.delete(:terms)
      assert {:error, changeset} = Accounts.register_user(attrs)
      assert "please agree to the Terms of use" in Keepsakes.DataCase.errors_on(changeset).terms

      {:ok, user} = Accounts.register_user(Map.put(attrs, :terms, true))
      assert user.terms_version == Accounts.terms_version()
      assert user.terms_accepted_at
      assert Accounts.terms_accepted?(user)
    end

    test "the sign-up form shows the checkbox and link", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/auth/register")
      assert has_element?(lv, "#registration-terms input[type=checkbox]")
      assert has_element?(lv, ~s(#registration-terms-link[href="/terms"]))
    end
  end

  describe "installable app" do
    test "manifest, service worker and offline page are served", %{conn: conn} do
      conn = get(conn, "/manifest.webmanifest")
      assert [type] = get_resp_header(conn, "content-type")
      assert type =~ "application/manifest+json"
      assert %{"start_url" => "/app", "icons" => [_ | _]} = Jason.decode!(conn.resp_body)

      sw = get(build_conn(), "/sw.js")
      assert sw.status == 200
      assert sw.resp_body =~ "never cached" or sw.resp_body =~ "NEVER cached"

      assert get(build_conn(), "/offline.html").status == 200
      assert get(build_conn(), "/images/icons/icon-192.png").status == 200
    end

    test "pages link the manifest", %{conn: conn} do
      assert conn |> get(~p"/terms") |> html_response(200) =~ ~s(rel="manifest")
    end
  end
end
