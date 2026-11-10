defmodule Keepsakes.MusicTest do
  use Keepsakes.DataCase, async: true

  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures
  import Keepsakes.BillingFixtures

  alias Keepsakes.Accounts.Scope
  alias Keepsakes.{Accounts, Albums, Music, Repo, Storage}

  @mp3 <<"ID3", 4, 0, 0, 0, 0, 0, 0>> <> :binary.copy(<<0>>, 2000)
  @m4a <<0, 0, 0, 24, "ftyp", "M4A ", 0, 0, 0, 0>> <> :binary.copy(<<0>>, 2000)

  setup do
    owner = user_fixture()
    put_on_plan(owner, "plus")
    {:ok, true} = FunWithFlags.enable(:slideshow_music, for_actor: owner)
    scope = Scope.for_user(owner)
    %{owner: owner, scope: scope, album: album_fixture(scope)}
  end

  defp file(binary, name) do
    path = Path.join(System.tmp_dir!(), "music-#{System.unique_integer([:positive])}-#{name}")
    File.write!(path, binary)
    %{path: path, filename: name, bytes: byte_size(binary)}
  end

  test "sniffs MP3 and M4A by their bytes" do
    assert {:ok, ".mp3", "audio/mpeg"} = Music.sniff(file(@mp3, "a.mp3").path)
    assert {:ok, ".mp3", "audio/mpeg"} = Music.sniff(file(<<0xFF, 0xFB, 0x90, 0>>, "b.mp3").path)
    assert {:ok, ".m4a", "audio/mp4"} = Music.sniff(file(@m4a, "c.m4a").path)
    assert {:error, :not_audio} = Music.sniff(file("hello, not music", "d.mp3").path)
  end

  test "upload sets the album's track and counts as storage", %{scope: scope, album: album} do
    assert {:ok, track} = Music.upload(scope, album, file(@mp3, "Song.mp3"))
    assert track.source == "upload"
    assert track.filename == "Song.mp3"
    assert Storage.exists?(track.storage_key)

    album = Repo.reload!(album)
    assert album.music_track_id == track.id
    assert Albums.storage_used(scope) == byte_size(@mp3)
  end

  test "replacing removes the old file; removing clears it", %{scope: scope, album: album} do
    {:ok, old} = Music.upload(scope, album, file(@mp3, "one.mp3"))
    {:ok, new} = Music.upload(scope, Repo.reload!(album), file(@m4a, "two.m4a"))

    refute Storage.exists?(old.storage_key)
    assert Albums.storage_used(scope) == byte_size(@m4a)

    {:ok, album} = Music.remove(scope, Repo.reload!(album))
    assert album.music_track_id == nil
    refute Storage.exists?(new.storage_key)
    assert Albums.storage_used(scope) == 0
  end

  test "refuses what isn't music or is too big", %{scope: scope, album: album} do
    assert {:error, :not_audio} = Music.upload(scope, album, file("not music", "x.mp3"))

    big = %{file(@mp3, "big.mp3") | bytes: Music.max_bytes() + 1}
    assert {:error, :too_large} = Music.upload(scope, album, big)
  end

  test "needs the terms of use agreed", %{owner: owner, scope: scope, album: album} do
    owner =
      owner |> Ecto.Changeset.change(terms_version: nil, terms_accepted_at: nil) |> Repo.update!()

    scope = %{scope | user: owner}

    assert {:error, :terms} = Music.upload(scope, album, file(@mp3, "a.mp3"))
    assert {:ok, _} = Music.upload(scope, album, file(@mp3, "a.mp3"), true)
    assert Accounts.terms_accepted?(Repo.reload!(owner))
  end

  test "needs the flag and the plan", %{owner: owner, scope: scope, album: album} do
    put_on_plan(owner, "free")
    assert {:error, :not_in_plan} = Music.upload(scope, album, file(@mp3, "a.mp3"))

    put_on_plan(owner, "plus")
    {:ok, false} = FunWithFlags.disable(:slideshow_music, for_actor: owner)
    assert {:error, :flag_off} = Music.upload(scope, album, file(@mp3, "a.mp3"))
  end

  test "the owner's storage limit applies", %{owner: owner, scope: scope, album: album} do
    put_on_plan(owner, plan_fixture(%{"slideshow_music" => true, "storage_bytes" => 100}))

    assert {:error, {:over_limit, :storage_bytes, 0, 100}} =
             Music.upload(scope, album, file(@mp3, "a.mp3"))
  end

  test "only the owner adds music", %{album: album} do
    assert_raise Keepsakes.Albums.NotAllowed, fn ->
      Music.upload(user_scope_fixture(), album, file(@mp3, "a.mp3"))
    end
  end
end
