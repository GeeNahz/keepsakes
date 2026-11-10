defmodule Keepsakes.SharingTest do
  use Keepsakes.DataCase, async: true

  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures

  alias Keepsakes.{Albums, Sharing}
  alias Keepsakes.Sharing.ShareLink

  setup do
    scope = user_scope_fixture()
    %{scope: scope, album: album_fixture(scope, name: "Our Little One")}
  end

  describe "creating a link" do
    test "auto mode makes a random 6-digit code and a slug", %{scope: scope, album: album} do
      assert {:ok, link} = Sharing.create_link(scope, album, "auto")

      assert link.slug =~ ~r/\Aour-little-one-[A-Z2-9]{4}\z/
      assert link.code =~ ~r/\A\d{6}\z/
      assert link.code_origin == "auto"
      assert link.code_version == 1
      assert Sharing.get_link(scope, album).id == link.id
      assert Sharing.display_url(link) =~ "/a/#{link.slug}"
    end

    test "the code is encrypted at rest", %{scope: scope, album: album} do
      {:ok, link} = Sharing.create_link(scope, album, "manual", "482917")

      %{rows: [[raw]]} =
        Repo.query!("SELECT code FROM share_links WHERE id = $1", [Ecto.UUID.dump!(link.id)])

      refute raw =~ "482917"
      assert Repo.reload!(link).code == "482917"
    end

    test "manual codes must be 6 digits and not guessable", %{scope: scope, album: album} do
      assert {:error, "Enter exactly 6 numbers."} =
               Sharing.create_link(scope, album, "manual", "12a456")

      assert {:error, "Enter exactly 6 numbers."} =
               Sharing.create_link(scope, album, "manual", "12345")

      for weak <- ~w(000000 111111 123456 987654) do
        assert {:error, "That code is too easy" <> _} =
                 Sharing.create_link(scope, album, "manual", weak)
      end

      assert {:ok, %ShareLink{code: "482917", code_origin: "manual"}} =
               Sharing.create_link(scope, album, "manual", " 482917 ")
    end

    test "one link per album", %{scope: scope, album: album} do
      {:ok, _} = Sharing.create_link(scope, album, "auto")
      assert {:error, %Ecto.Changeset{}} = Sharing.create_link(scope, album, "auto")
    end

    test "other owners can't share or read the link", %{scope: scope, album: album} do
      {:ok, _} = Sharing.create_link(scope, album, "auto")
      intruder = user_scope_fixture()

      assert_raise FunctionClauseError, fn -> Sharing.create_link(intruder, album, "auto") end
      assert_raise FunctionClauseError, fn -> Sharing.get_link(intruder, album) end
    end
  end

  describe "managing a link" do
    setup %{scope: scope, album: album} do
      {:ok, link} = Sharing.create_link(scope, album, "manual", "482917")
      %{link: link}
    end

    test "changing the code bumps the version", %{scope: scope, link: link} do
      assert {:ok, link} = Sharing.change_code(scope, link, "auto")
      assert link.code_version == 2
      assert link.code_origin == "auto"
      refute link.code == "482917"

      assert {:ok, %ShareLink{code: "305172", code_version: 3}} =
               Sharing.change_code(scope, link, "manual", "305172")

      assert {:error, _} = Sharing.change_code(scope, link, "manual", "111111")
    end

    test "settings set the expiry from days", %{scope: scope, link: link} do
      assert {:ok, link} =
               Sharing.update_settings(scope, link, %{
                 "expires_in" => "7",
                 "default_view" => "slideshow",
                 "allow_downloads" => "true",
                 "show_details" => "false"
               })

      assert DateTime.diff(link.expires_at, DateTime.utc_now(), :day) in 6..7

      assert {link.default_view, link.allow_downloads, link.show_details} ==
               {"slideshow", true, false}

      refute ShareLink.expired?(link, DateTime.utc_now())
      assert ShareLink.expired?(link, DateTime.add(DateTime.utc_now(), 8, :day))

      assert {:ok, %ShareLink{expires_at: nil}} =
               Sharing.update_settings(scope, link, %{"expires_in" => "never"})

      assert {:error, _} = Sharing.update_settings(scope, link, %{"default_view" => "carousel"})
    end

    test "turning sharing off removes the link", %{scope: scope, album: album, link: link} do
      assert {:ok, _} = Sharing.delete_link(scope, link)
      assert Sharing.get_link(scope, album) == nil
      assert Sharing.get_link_by_slug(link.slug) == nil
    end
  end

  describe "guest side" do
    setup %{scope: scope, album: album} do
      {:ok, link} = Sharing.create_link(scope, album, "manual", "482917")
      %{link: link}
    end

    test "finds the link by slug with album and owner", %{link: link, album: album} do
      found = Sharing.get_link_by_slug(link.slug)
      assert found.album.id == album.id
      assert found.user.first_name
      assert Sharing.get_link_by_slug("nope") == nil
    end

    test "code_matches?/2", %{link: link} do
      assert Sharing.code_matches?(link, "482917")
      assert Sharing.code_matches?(link, " 482917\n")
      refute Sharing.code_matches?(link, "482918")
      refute Sharing.code_matches?(link, "")
      refute Sharing.code_matches?(link, nil)
    end

    test "record_open/1 counts visits", %{link: link} do
      :ok = Sharing.record_open(link)
      :ok = Sharing.record_open(link)
      link = Repo.reload!(link)
      assert link.open_count == 2
      assert link.last_opened_at
    end

    test "guests only see complete, processed, published memories", %{scope: scope, album: album} do
      ready = memory_fixture(scope, album, %{title: "Ready", month: 4, year: 2019})
      undated = memory_fixture(scope, album, %{title: "Undated"})
      _draft = draft_fixture(scope, album)

      for m <- [ready, undated] do
        Repo.update_all(from(x in Albums.Memory, where: x.id == ^m.id),
          set: [processing: "ready"]
        )
      end

      assert [%{id: id}] = Sharing.guest_memories(album)
      assert id == ready.id
      assert Sharing.guest_memory(album, ready.id).id == ready.id
      assert Sharing.guest_memory(album, undated.id) == nil
      assert Sharing.guest_memory(album, "not-a-uuid") == nil
    end
  end
end
