defmodule Keepsakes.AlbumsTest do
  use Keepsakes.DataCase, async: true
  use Oban.Testing, repo: Keepsakes.Repo

  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures

  alias Keepsakes.{Albums, Storage}
  alias Keepsakes.Albums.{Album, Memory}
  alias Keepsakes.Media.{ProcessMemory, Purge}

  setup do
    %{scope: user_scope_fixture()}
  end

  describe "albums" do
    test "create_album/2 slugs the name uniquely per owner", %{scope: scope} do
      assert {:ok, %Album{slug: "our-little-one"}} =
               Albums.create_album(scope, %{name: "  Our   Little One "})

      assert {:ok, %Album{slug: "our-little-one-2", name: "Our Little One!"}} =
               Albums.create_album(scope, %{name: "Our Little One!"})

      other = user_scope_fixture()

      assert {:ok, %Album{slug: "our-little-one"}} =
               Albums.create_album(other, %{name: "Our little one"})
    end

    test "create_album/2 validates", %{scope: scope} do
      assert {:error, changeset} = Albums.create_album(scope, %{name: " "})
      assert "Give your album a name" in errors_on(changeset).name

      assert {:error, changeset} =
               Albums.create_album(scope, %{name: "A", description: String.duplicate("x", 141)})

      assert errors_on(changeset).description != []
    end

    test "slugify/1 handles accents and symbols" do
      assert Album.slugify("Été à Lagos — 2023") == "ete-a-lagos-2023"
      assert Album.slugify("🎉🎉") == "album"
    end

    test "list_albums/1 counts published memories and is scoped", %{scope: scope} do
      album = album_fixture(scope, name: "First")
      memory_fixture(scope, album, %{title: "One"})
      _draft = draft_fixture(scope, album)

      assert [%Album{name: "First", memories_count: 1}] = Albums.list_albums(scope)
      assert Albums.list_albums(user_scope_fixture()) == []
    end

    test "get_album_by_slug!/2 never returns another owner's album", %{scope: scope} do
      album = album_fixture(scope)
      assert Albums.get_album_by_slug!(scope, album.slug).id == album.id

      assert_raise Ecto.NoResultsError, fn ->
        Albums.get_album_by_slug!(user_scope_fixture(), album.slug)
      end
    end
  end

  describe "drafts and publishing" do
    test "create_draft/3 stores the original and queues processing", %{scope: scope} do
      album = album_fixture(scope)
      memory = draft_fixture(scope, album, filename: "../IMG_2041.jpg")

      assert memory.status == "draft"
      assert memory.processing == "pending"
      assert memory.original_filename == "IMG_2041.jpg"
      assert memory.storage_prefix =~ "users/#{scope.user.id}/albums/#{album.id}/memories/"
      assert Storage.exists?(Memory.original_key(memory))
      assert_enqueued(worker: ProcessMemory, args: %{memory_id: memory.id})
    end

    test "processing makes variants, fills date and deletes the original", %{scope: scope} do
      album = album_fixture(scope)
      memory = draft_fixture(scope, album, taken: "2019:04:12 10:00:00")
      Albums.subscribe(scope)

      assert :ok = perform_job(ProcessMemory, %{memory_id: memory.id})

      memory = Albums.get_memory!(scope, memory.id)
      assert memory.processing == "ready"
      assert {memory.month, memory.year} == {4, 2019}
      assert memory.taken_on == ~D[2019-04-12]
      assert memory.stored_bytes > 0
      assert {memory.width, memory.height} == {1200, 800}
      refute Storage.exists?(Memory.original_key(memory))
      for w <- Memory.variants(), do: assert(Storage.exists?(Memory.variant_key(memory, w)))

      assert_receive {:memory_updated, %Memory{id: id, processing: "ready"}} when id == memory.id
    end

    test "EXIF never overwrites a date or place the owner already typed", %{scope: scope} do
      album = album_fixture(scope)
      memory = draft_fixture(scope, album, taken: "2019:04:12 10:00:00")
      {:ok, _} = Albums.update_memory(scope, memory, %{year: 2020, place: "Home"})

      :ok = perform_job(ProcessMemory, %{memory_id: memory.id})

      memory = Albums.get_memory!(scope, memory.id)
      assert {memory.month, memory.year, memory.place} == {nil, 2020, "Home"}
    end

    test "unreadable uploads are marked failed without retrying", %{scope: scope} do
      album = album_fixture(scope)
      memory = draft_fixture(scope, album, binary: "not an image")

      assert {:cancel, _} = perform_job(ProcessMemory, %{memory_id: memory.id})

      assert %Memory{processing: "failed", processing_error: "We couldn't read" <> _} =
               Albums.get_memory!(scope, memory.id)
    end

    test "processing a deleted memory is a no-op", %{scope: scope} do
      assert :ok = perform_job(ProcessMemory, %{memory_id: Ecto.UUID.generate()})
      _ = scope
    end

    test "publish_drafts/2 publishes all drafts and picks a cover", %{scope: scope} do
      album = album_fixture(scope)
      later = draft_fixture(scope, album)
      earlier = draft_fixture(scope, album)
      {:ok, _} = Albums.update_memory(scope, later, %{title: "Later", month: 5, year: 2020})
      {:ok, _} = Albums.update_memory(scope, earlier, %{title: "Earlier", month: 1, year: 2019})

      assert {:ok, 2} = Albums.publish_drafts(scope, album)
      assert Albums.list_drafts(scope, album) == []
      assert Enum.map(Albums.list_memories(scope, album), & &1.title) == ["Earlier", "Later"]
      assert Repo.reload!(album).cover_memory_id == earlier.id
    end

    test "memories without a date sort last", %{scope: scope} do
      album = album_fixture(scope)
      memory_fixture(scope, album, %{title: "Undated"})
      memory_fixture(scope, album, %{title: "Dated", month: 3, year: 2021})

      assert Enum.map(Albums.list_memories(scope, album), & &1.title) == ["Dated", "Undated"]
    end

    test "discard_drafts/2 deletes drafts and queues file removal", %{scope: scope} do
      album = album_fixture(scope)
      published = memory_fixture(scope, album, %{title: "Keep"})
      draft = draft_fixture(scope, album)

      assert {:ok, 1} = Albums.discard_drafts(scope, album)
      assert Albums.list_drafts(scope, album) == []
      assert [%{id: id}] = Albums.list_memories(scope, album)
      assert id == published.id

      assert_enqueued(worker: Purge, args: %{keys: Memory.all_keys(draft)})
      assert :ok = perform_job(Purge, %{keys: Memory.all_keys(draft)})
      refute Storage.exists?(Memory.original_key(draft))
    end
  end

  describe "editing" do
    test "update_memory/3 validates the form fields", %{scope: scope} do
      memory = draft_fixture(scope, album_fixture(scope))

      assert {:error, changeset} =
               Albums.update_memory(scope, memory, %{
                 month: 13,
                 year: Date.utc_today().year + 1,
                 caption: String.duplicate("x", 281)
               })

      assert %{month: [_], year: [_], caption: [_]} = errors_on(changeset)
      assert {:ok, %Memory{title: nil}} = Albums.update_memory(scope, memory, %{title: "   "})
    end

    test "ready?/1 and missing/1", %{scope: scope} do
      memory = draft_fixture(scope, album_fixture(scope))
      refute Memory.ready?(memory)
      assert Memory.missing(memory) == "name + date"
      assert Memory.missing(%{memory | title: "Hi"}) == "date"
      assert Memory.missing(%{memory | month: 1, year: 2020}) == "name"
      assert Memory.ready?(%{memory | title: "Hi", month: 1, year: 2020})
    end

    test "set_people/3 trims and de-duplicates", %{scope: scope} do
      memory = draft_fixture(scope, album_fixture(scope))

      assert {:ok, %Memory{people: ["Ada", "Mum"]}} =
               Albums.set_people(scope, memory, [" Ada ", "ada", "", "Mum"])

      assert {:error, _} = Albums.set_people(scope, memory, [String.duplicate("x", 41)])
    end

    test "other owners can't edit or delete", %{scope: scope} do
      memory = draft_fixture(scope, album_fixture(scope))
      intruder = user_scope_fixture()

      assert_raise FunctionClauseError, fn ->
        Albums.update_memory(intruder, memory, %{title: "x"})
      end

      assert_raise FunctionClauseError, fn -> Albums.delete_memory(intruder, memory) end
      assert_raise Ecto.NoResultsError, fn -> Albums.get_memory!(intruder, memory.id) end
    end

    test "set_cover/3 only accepts memories of the album", %{scope: scope} do
      album = album_fixture(scope)
      memory = memory_fixture(scope, album, %{title: "x"})
      other_album = album_fixture(scope)

      assert {:ok, %Album{cover_memory_id: nil}} = Albums.set_cover(scope, album, nil)
      assert {:ok, %Album{cover_memory_id: id}} = Albums.set_cover(scope, album, memory)
      assert id == memory.id
      assert_raise CaseClauseError, fn -> Albums.set_cover(scope, other_album, memory) end
    end

    test "deleting the cover clears it", %{scope: scope} do
      album = album_fixture(scope)
      memory = memory_fixture(scope, album, %{title: "x"})
      assert Repo.reload!(album).cover_memory_id == memory.id

      {:ok, _} = Albums.delete_memory(scope, memory)
      assert Repo.reload!(album).cover_memory_id == nil
    end
  end

  test "storage_used/1 counts originals until processed, then the variants", %{scope: scope} do
    album = album_fixture(scope)
    memory = draft_fixture(scope, album)
    assert Albums.storage_used(scope) == memory.original_bytes

    :ok = perform_job(ProcessMemory, %{memory_id: memory.id})
    assert Albums.storage_used(scope) == Albums.get_memory!(scope, memory.id).stored_bytes
    assert Albums.storage_used(user_scope_fixture()) == 0
  end
end
