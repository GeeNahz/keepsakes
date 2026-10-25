defmodule Keepsakes.EntitlementsTest do
  use Keepsakes.DataCase, async: true

  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures
  import Keepsakes.BillingFixtures

  alias Keepsakes.{Albums, Entitlements, Sharing, Templates}

  setup do
    scope = user_scope_fixture()
    %{scope: scope, user: scope.user}
  end

  describe "values" do
    test "trial users get Pro, Free users the Free limits", %{scope: scope, user: user} do
      assert Entitlements.limit(scope, :max_albums) == :unlimited
      assert Entitlements.can?(scope, :premium_templates)

      put_on_plan(user, "free")
      assert Entitlements.limit(scope, :max_albums) == 2
      assert Entitlements.limit(scope, :storage_bytes) == 1024 * 1024 * 1024
      refute Entitlements.can?(scope, :guest_downloads)
      assert Entitlements.max_upload_mb(scope) == 10
    end

    test "check/4 allows up to the limit", %{scope: scope, user: user} do
      put_on_plan(user, "free")
      assert :ok = Entitlements.check(scope, :max_albums, 1)

      assert {:error, {:over_limit, :max_albums, 2, 2}} =
               Entitlements.check(scope, :max_albums, 2)

      assert Entitlements.message({:over_limit, :max_albums, 2, 2}) ==
               "Your plan includes 2 albums."
    end
  end

  describe "enforced in the contexts" do
    test "albums stop at the plan's limit", %{scope: scope, user: user} do
      put_on_plan(user, "free")
      album_fixture(scope)
      album_fixture(scope)

      assert {:error, {:over_limit, :max_albums, 2, 2}} =
               Albums.create_album(scope, %{name: "Third"})
    end

    test "photos stop at the album's limit", %{scope: scope, user: user} do
      put_on_plan(user, plan_fixture(%{"max_memories_per_album" => 1}))
      album = album_fixture(scope)
      draft_fixture(scope, album)

      assert {:error, {:over_limit, :max_memories_per_album, 1, 1}} = try_draft(scope, album)
      assert Albums.list_drafts(scope, album) |> length() == 1
    end

    test "storage stops at the plan's limit", %{scope: scope, user: user} do
      album = album_fixture(scope)
      first = draft_fixture(scope, album)
      put_on_plan(user, plan_fixture(%{"storage_bytes" => first.original_bytes + 10}))

      assert {:error, {:over_limit, :storage_bytes, _used, _max}} = try_draft(scope, album)
    end

    test "photos bigger than the plan allows are refused", %{scope: scope, user: user} do
      put_on_plan(user, plan_fixture(%{"max_upload_mb" => 1}))
      album = album_fixture(scope)

      assert {:error, {:over_limit, :max_upload_mb, 1, 1}} =
               try_draft(scope, album, 2_000_000)
    end

    test "going over after a downgrade keeps everything", %{scope: scope, user: user} do
      album = album_fixture(scope)
      album_fixture(scope)
      album_fixture(scope)
      memory = draft_fixture(scope, album)
      put_on_plan(user, "free")

      assert length(Albums.list_albums(scope)) == 3
      assert Albums.get_memory!(scope, memory.id)
      assert {:error, {:over_limit, :max_albums, 3, 2}} = Albums.create_album(scope, %{name: "4"})
    end
  end

  describe "premium templates" do
    test "need the feature to use", %{scope: scope, user: user} do
      album = album_fixture(scope)
      daylight = Templates.get_template(scope, "daylight")
      assert daylight.premium

      put_on_plan(user, "free")
      assert {:error, :premium} = Templates.set_album_template(scope, album, daylight)
      assert {:error, :premium} = Templates.set_default_template(scope, daylight)
    end

    test "fall back to the default when the plan drops them", %{scope: scope, user: user} do
      album = album_fixture(scope)
      daylight = Templates.get_template(scope, "daylight")
      {:ok, album} = Templates.set_album_template(scope, album, daylight)
      {:ok, _} = Templates.set_default_template(scope, daylight)
      assert Templates.for_album(album).slug == "daylight"

      put_on_plan(user, "free")
      assert Templates.for_album(album).slug == "trail"

      scope = Keepsakes.Accounts.Scope.for_user(Keepsakes.Accounts.get_user!(user.id))
      assert Templates.default_for(scope).slug == "trail"
    end
  end

  describe "sharing features" do
    test "guest downloads follow the plan", %{scope: scope, user: user} do
      album = album_fixture(scope)
      link = share_link_fixture(scope, album, %{allow_downloads: true})
      assert Sharing.downloads_allowed?(link)

      put_on_plan(user, "free")
      refute Sharing.downloads_allowed?(link)

      {:ok, link} = Sharing.update_settings(scope, link, %{allow_downloads: true})
      refute link.allow_downloads
    end

    test "branding shows only on plans without remove_branding", %{user: user} do
      refute Sharing.branding?(user.id)
      put_on_plan(user, "free")
      assert Sharing.branding?(user.id)
    end
  end

  defp try_draft(scope, album, bytes \\ nil) do
    binary = jpeg()
    path = Path.join(System.tmp_dir!(), "ks-limit-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, binary)

    result =
      Albums.create_draft(scope, album, %{
        path: path,
        filename: "IMG.jpg",
        bytes: bytes || byte_size(binary)
      })

    File.rm(path)
    result
  end
end
