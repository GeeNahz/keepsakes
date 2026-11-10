defmodule Keepsakes.Sharing.EngagementTest do
  use Keepsakes.DataCase, async: true

  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures
  import Keepsakes.BillingFixtures

  alias Keepsakes.Accounts.Scope
  alias Keepsakes.{Albums, Sharing}
  alias Keepsakes.Albums.Memory
  alias Keepsakes.Sharing.Engagement

  setup do
    owner = user_fixture()
    put_on_plan(owner, "plus")
    scope = Scope.for_user(owner)
    album = album_fixture(scope)
    link = share_link_fixture(scope, album)
    %{owner: owner, scope: scope, album: album, link: link}
  end

  defp enable(user, flags),
    do: for(f <- flags, do: {:ok, true} = FunWithFlags.enable(f, for_actor: user))

  defp turn_on(scope, link, attrs) do
    {:ok, link} = Engagement.update_features(scope, link, attrs)
    Repo.preload(%{link | user: nil, album: nil}, [:user, :album], force: true)
  end

  defp upload(binary \\ jpeg()) do
    path = Path.join(System.tmp_dir!(), "guest-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, binary)
    %{path: path, filename: "IMG_9.jpg", bytes: byte_size(binary)}
  end

  describe "available/1 and switches" do
    test "needs the flag and the plan", %{owner: owner, scope: scope} do
      assert %{guest_uploads: :flag_off, reactions_guestbook: :flag_off, time_capsule: :ok} =
               Engagement.available(scope)

      enable(owner, [:guest_uploads, :reactions_guestbook])
      assert %{guest_uploads: :ok, reactions_guestbook: :ok} = Engagement.available(scope)

      put_on_plan(owner, "free")

      assert %{guest_uploads: :not_in_plan, time_capsule: :not_in_plan} =
               Engagement.available(scope)
    end

    test "switches the owner doesn't have stay off", %{scope: scope, link: link} do
      {:ok, link} = Engagement.update_features(scope, link, %{"guest_uploads" => "true"})
      refute link.guest_uploads
    end

    test "a downgrade closes them without turning them off", %{
      owner: owner,
      scope: scope,
      link: link
    } do
      enable(owner, [:guest_uploads])
      link = turn_on(scope, link, %{"guest_uploads" => "true"})
      assert Engagement.uploads_open?(link)

      put_on_plan(owner, "free")
      refute Engagement.uploads_open?(link)
      assert link.guest_uploads
    end
  end

  describe "guest uploads" do
    setup %{owner: owner, scope: scope, link: link} do
      enable(owner, [:guest_uploads])
      %{link: turn_on(scope, link, %{"guest_uploads" => "true"})}
    end

    test "wait for approval and count against the owner", %{
      scope: scope,
      album: album,
      link: link
    } do
      assert {:ok, memory} =
               Engagement.add_photo(link, "visitor-1", upload(), %{
                 guest_name: " Aunt Bisi ",
                 title: "Cake",
                 month: 5,
                 year: 2020,
                 caption: nil
               })

      assert %Memory{status: "submitted", source: "guest", guest_name: "Aunt Bisi", title: "Cake"} =
               memory

      assert memory.rights_confirmed_at
      assert memory.user_id == scope.user.id
      assert Albums.storage_used(scope) == memory.original_bytes

      # Hidden from guests and the owner's timeline until approved
      assert Sharing.guest_memories(album) == []
      assert Albums.list_memories(scope, album) == []
      assert [%{id: id}] = Albums.list_submitted(scope, album)
      assert id == memory.id

      {:ok, 1} = Albums.approve_submitted(scope, album)
      assert [%{status: "published"}] = Albums.list_memories(scope, album)
    end

    test "declining deletes the photo", %{scope: scope, album: album, link: link} do
      {:ok, memory} = Engagement.add_photo(link, "v", upload(), %{guest_name: "Bisi"})
      {:ok, _} = Albums.delete_memory(scope, memory)
      assert Albums.list_submitted(scope, album) == []
    end

    test "a name is required and the switch must be on", %{scope: scope, link: link} do
      assert {:error, :name} = Engagement.add_photo(link, "v", upload(), %{guest_name: "  "})

      link = turn_on(scope, link, %{"guest_uploads" => "false"})
      assert {:error, :closed} = Engagement.add_photo(link, "v", upload(), %{guest_name: "Bisi"})
    end

    test "the owner's storage limit applies", %{owner: owner, link: link} do
      put_on_plan(owner, plan_fixture(%{"guest_uploads" => true, "storage_bytes" => 10}))

      assert {:error, {:over_limit, :storage_bytes, _, 10}} =
               Engagement.add_photo(link, "v", upload(), %{guest_name: "Bisi"})
    end

    test "editors review; viewers can't", %{scope: scope, album: album, link: link} do
      {:ok, _} = Engagement.add_photo(link, "v", upload(), %{guest_name: "Bisi"})
      viewer = collaborator(scope, album, "viewer")

      assert_raise Keepsakes.Albums.NotAllowed, fn -> Albums.list_submitted(viewer, album) end
      editor = collaborator(scope, album, "editor")
      assert {:ok, 1} = Albums.approve_submitted(editor, album)
    end
  end

  describe "hearts" do
    setup %{owner: owner, scope: scope, album: album, link: link} do
      enable(owner, [:reactions_guestbook])
      memory = guest_memory_fixture(scope, album)
      %{memory: memory, link: turn_on(scope, link, %{"reactions_guestbook" => "true"})}
    end

    test "one per visitor, toggled, broadcast", %{album: album, link: link, memory: memory} do
      Engagement.subscribe(album)

      assert {:ok, true, 1} = Engagement.toggle_heart(link, "a", memory.id)
      assert_receive {:hearts, id, 1} when id == memory.id
      assert {:ok, true, 2} = Engagement.toggle_heart(link, "b", memory.id)
      assert {:ok, false, 1} = Engagement.toggle_heart(link, "a", memory.id)

      assert Engagement.heart_counts(album) == %{memory.id => 1}
      assert Engagement.hearted(album, "b") == MapSet.new([memory.id])
    end

    test "only on photos guests can see, and only when on", %{
      scope: scope,
      album: album,
      link: link
    } do
      draft = draft_fixture(scope, album)
      assert {:error, :not_found} = Engagement.toggle_heart(link, "a", draft.id)

      link = turn_on(scope, link, %{"reactions_guestbook" => "false"})
      assert {:error, :closed} = Engagement.toggle_heart(link, "a", Ecto.UUID.generate())
    end
  end

  describe "guestbook" do
    setup %{owner: owner, scope: scope, link: link} do
      enable(owner, [:reactions_guestbook])
      %{link: turn_on(scope, link, %{"reactions_guestbook" => "true"})}
    end

    test "notes wait for approval; the writer sees their own", %{
      scope: scope,
      album: album,
      link: link
    } do
      {:ok, note} = Engagement.sign(link, "writer", %{"name" => "Bisi", "message" => "Lovely!"})

      assert [%{id: id, status: "pending"}] = Engagement.guestbook(album, "writer")
      assert id == note.id
      assert Engagement.guestbook(album, "someone-else") == []
      assert [_] = Engagement.pending_notes(scope, album)

      {:ok, _} = Engagement.approve_note(scope, album, note.id)
      assert [%{status: "approved"}] = Engagement.guestbook(album, "someone-else")

      {:ok, _} = Engagement.delete_note(scope, album, note.id)
      assert Engagement.guestbook(album, "writer") == []
    end

    test "validates the note", %{link: link} do
      assert {:error, changeset} =
               Engagement.sign(link, "w", %{"name" => "", "message" => String.duplicate("x", 501)})

      assert %{name: [_], message: [_]} = errors_on(changeset)
    end

    test "the digest counts what's waiting", %{owner: owner, link: link} do
      {:ok, _} = Engagement.sign(link, "w", %{"name" => "Bisi", "message" => "Hi"})
      assert Engagement.waiting_for_owner(owner.id) == %{photos: 0, notes: 1}
    end
  end

  # An accepted collaborator, without going through the email
  defp collaborator(scope, album, role) do
    user = user_fixture()

    Repo.insert!(%Keepsakes.Albums.Member{
      album_id: album.id,
      user_id: user.id,
      invited_by_id: scope.user.id,
      email: user.email,
      role: role,
      invited_at: DateTime.utc_now(:second),
      accepted_at: DateTime.utc_now(:second)
    })

    Scope.for_user(user)
  end
end
