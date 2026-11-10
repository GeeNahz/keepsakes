defmodule KeepsakesWeb.SettingsLive.PrivacyTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Keepsakes.AlbumsFixtures

  alias Keepsakes.{Accounts, Exports, Repo, Sharing, Storage}
  alias Keepsakes.Exports.DataExport

  setup :register_and_log_in_user

  # The sign-up fixture's confirmation email
  setup do
    assert_email_sent(subject: "Confirm your Keepsake account")
    :ok
  end

  describe "export everything" do
    test "builds a zip of photos and details, emailed and downloadable", %{
      conn: conn,
      scope: scope
    } do
      album = album_fixture(scope, name: "Our Little One")
      memory = guest_memory_fixture(scope, album, %{title: "First birthday", caption: "Cake!"})
      :ok = Storage.put(Keepsakes.Albums.Memory.variant_key(memory, 2400), "webp-bytes")

      {:ok, lv, _html} = live(conn, ~p"/app/settings/privacy")
      lv |> element("#start-export") |> render_click()
      assert has_element?(lv, "#export-status", "Preparing your export")

      assert %{success: 1} = Oban.drain_queue(queue: :default)
      export = Repo.one!(DataExport)
      assert export.status == "ready"
      # The open page updates by itself
      assert has_element?(lv, "#download-export")
      assert_email_sent(subject: "Your Keepsake export is ready")

      {:ok, zip} = Storage.get(export.storage_key)
      {:ok, files} = :zip.unzip(zip, [:memory])
      names = Enum.map(files, fn {name, _} -> to_string(name) end)
      assert "#{album.slug}/001 First birthday.webp" in names

      {_, json} =
        Enum.find(files, fn {name, _} -> to_string(name) == "#{album.slug}/album.json" end)

      assert %{"name" => "Our Little One", "memories" => [%{"caption" => "Cake!"}]} =
               Jason.decode!(json)

      download = get(conn, ~p"/app/settings/privacy/exports/#{export.id}")
      assert redirected_to(download) =~ "/media/"
    end

    test "expired exports are removed and their link explains", %{conn: conn, scope: scope} do
      {:ok, export} = Exports.request(scope)
      :ok = Storage.put("users/#{scope.user.id}/exports/#{export.id}.zip", "zip")

      export =
        export
        |> Ecto.Changeset.change(
          status: "ready",
          storage_key: "users/#{scope.user.id}/exports/#{export.id}.zip",
          expires_at: DateTime.add(DateTime.utc_now(:second), -60)
        )
        |> Repo.update!()

      conn = get(conn, ~p"/app/settings/privacy/exports/#{export.id}")
      assert redirected_to(conn) == ~p"/app/settings/privacy"

      assert Exports.remove_expired() == 1
      refute Storage.exists?(export.storage_key)
    end
  end

  describe "delete account" do
    test "needs the email typed, then pauses the account", %{conn: conn, scope: scope, user: user} do
      album = album_fixture(scope)
      link = share_link_fixture(scope, album)

      {:ok, lv, _html} = live(conn, ~p"/app/settings/privacy")
      lv |> form("#delete-account-form", email: "wrong@example.com") |> render_submit()
      assert has_element?(lv, "#delete-error")

      assert {:error, {:redirect, %{to: "/"}}} =
               lv
               |> form("#delete-account-form", email: String.upcase(user.email))
               |> render_submit()

      assert Accounts.get_user!(user.id).deletion_requested_at
      assert Accounts.list_sessions(user) == []
      refute Sharing.get_link_by_slug(link.slug)
      assert_email_sent(subject: "Your Keepsake account will be deleted")
    end

    test "after 14 days everything is deleted", %{scope: scope, user: user} do
      album = album_fixture(scope)
      memory = draft_fixture(scope, album)
      {:ok, user, _} = Accounts.request_deletion(user)

      assert Accounts.purge_deleted() == 0

      assert Accounts.purge_deleted(DateTime.add(user.deletion_requested_at, 15, :day)) == 1
      refute Accounts.get_user(user.id)
      refute Storage.exists?(Keepsakes.Albums.Memory.original_key(memory))
    end
  end
end
