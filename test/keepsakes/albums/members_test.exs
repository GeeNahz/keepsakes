defmodule Keepsakes.Albums.MembersTest do
  use Keepsakes.DataCase, async: true

  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures
  import Keepsakes.BillingFixtures

  alias Keepsakes.Accounts.Scope
  alias Keepsakes.Albums
  alias Keepsakes.Albums.{Member, Members, NotAllowed}

  setup do
    owner = user_fixture(%{first_name: "Ngozi"})
    put_on_plan(owner, "plus")
    scope = Scope.for_user(owner)
    %{owner: owner, scope: scope, album: album_fixture(scope, name: "Our Little One")}
  end

  # Invites `user` as `role` and accepts with their account
  defp join_as(scope, album, user, role) do
    {:ok, _} = Members.invite(scope, album, %{"email" => user.email, "role" => role})
    token = invite_token()
    {:ok, _} = Members.accept(Scope.for_user(user), token)
    Scope.for_user(user)
  end

  # The latest invitation email (sign-up confirmations come through too)
  defp invite_email do
    receive do
      {:email, %Swoosh.Email{text_body: body} = email} ->
        if body =~ "/invites/", do: email, else: invite_email()
    after
      1000 -> flunk("no invitation email was sent")
    end
  end

  defp invite_token do
    [_, token] = Regex.run(~r{/invites/([\w-]+)}, invite_email().text_body)
    token
  end

  describe "roles" do
    test "owner, editor, viewer and strangers", %{scope: scope, album: album} do
      editor = join_as(scope, album, user_fixture(), "editor")
      viewer = join_as(scope, album, user_fixture(), "viewer")
      stranger = user_scope_fixture()

      assert Albums.role(scope, album) == :owner
      assert Albums.role(editor, album) == :editor
      assert Albums.role(viewer, album) == :viewer
      assert Albums.role(stranger, album) == nil

      assert Albums.can?(editor, album, :edit)
      refute Albums.can?(editor, album, :manage)
      assert Albums.can?(viewer, album, :view)
      refute Albums.can?(viewer, album, :edit)
    end

    test "a pending invitation gives no access", %{scope: scope, album: album} do
      invitee = user_fixture()
      {:ok, _} = Members.invite(scope, album, %{"email" => invitee.email, "role" => "editor"})
      assert Albums.role(Scope.for_user(invitee), album) == nil
    end

    test "editors add and edit photos, charged to the owner", %{scope: scope, album: album} do
      editor = join_as(scope, album, user_fixture(), "editor")

      memory = draft_fixture(editor, album)
      assert memory.user_id == scope.user.id
      assert Albums.storage_used(scope) == memory.original_bytes
      assert Albums.storage_used(editor) == 0

      assert {:ok, %{title: "Beach"}} = Albums.update_memory(editor, memory, %{title: "Beach"})
      assert {:ok, 1} = Albums.publish_drafts(editor, album)
      assert [%{id: id}] = Albums.list_memories(editor, album)
      assert id == memory.id
    end

    test "viewers see but can't change anything", %{scope: scope, album: album} do
      viewer = join_as(scope, album, user_fixture(), "viewer")
      memory = memory_fixture(scope, album, %{title: "Hello", month: 1, year: 2020})

      assert [_] = Albums.list_memories(viewer, album)
      assert Albums.get_memory!(viewer, album, memory.id)
      assert_raise NotAllowed, fn -> Albums.update_memory(viewer, memory, %{title: "x"}) end
      assert_raise NotAllowed, fn -> Albums.delete_memory(viewer, memory) end
      assert_raise NotAllowed, fn -> draft_fixture(viewer, album) end
    end

    test "strangers still can't read another owner's album", %{scope: scope, album: album} do
      memory = memory_fixture(scope, album, %{title: "Private", month: 1, year: 2020})
      stranger = user_scope_fixture()

      assert_raise NotAllowed, fn -> Albums.list_memories(stranger, album) end
      assert_raise NotAllowed, fn -> Albums.get_memory!(stranger, album, memory.id) end
      assert_raise NotAllowed, fn -> Albums.get_shared_album!(stranger, album.id) end
    end

    test "shared albums list for the collaborator, with role", %{scope: scope, album: album} do
      editor = join_as(scope, album, user_fixture(), "editor")
      assert [{shared, :editor}] = Albums.list_shared_albums(editor)
      assert shared.id == album.id
      assert shared.user.id == scope.user.id
      assert Albums.get_shared_album!(editor, album.id).id == album.id
    end
  end

  describe "invitations" do
    test "sends an email and records a pending member", %{scope: scope, album: album} do
      assert {:ok, %Member{email: "aunt@example.com", role: "viewer", accepted_at: nil}} =
               Members.invite(scope, album, %{"email" => " Aunt@Example.com ", "role" => "viewer"})

      assert invite_email().subject == "Ngozi Lovelace invited you to Our Little One"
    end

    test "refuses bad emails, duplicates and the owner", %{scope: scope, album: album} do
      assert {:error, %Ecto.Changeset{}} =
               Members.invite(scope, album, %{"email" => "nope", "role" => "editor"})

      {:ok, _} = Members.invite(scope, album, %{"email" => "a@example.com", "role" => "editor"})

      assert {:error, changeset} =
               Members.invite(scope, album, %{"email" => "a@example.com", "role" => "viewer"})

      assert "is already invited to this album" in errors_on(changeset).email

      assert {:error, changeset} =
               Members.invite(scope, album, %{"email" => scope.user.email, "role" => "editor"})

      assert "is your own account" in errors_on(changeset).email
    end

    test "seats count distinct people across albums", %{scope: scope, album: album} do
      other = album_fixture(scope)
      {:ok, _} = Members.invite(scope, album, %{"email" => "a@example.com", "role" => "editor"})
      {:ok, _} = Members.invite(scope, other, %{"email" => "a@example.com", "role" => "viewer"})
      assert Members.seats_used(scope) == 1

      {:ok, _} = Members.invite(scope, album, %{"email" => "b@example.com", "role" => "editor"})
      assert Members.seats_used(scope) == 2

      # Plus has 2 seats
      assert {:error, {:over_limit, :collaborator_seats, 2, 2}} =
               Members.invite(scope, album, %{"email" => "c@example.com", "role" => "editor"})

      # Someone already on another album still fits
      assert {:ok, _} =
               Members.invite(scope, other, %{"email" => "b@example.com", "role" => "editor"})
    end

    test "the Free plan has no seats", %{owner: owner, scope: scope, album: album} do
      put_on_plan(owner, "free")

      assert {:error, {:over_limit, :collaborator_seats, 0, 0}} =
               Members.invite(scope, album, %{"email" => "a@example.com", "role" => "editor"})
    end

    test "only the owner manages people", %{scope: scope, album: album} do
      editor = join_as(scope, album, user_fixture(), "editor")

      assert_raise NotAllowed, fn ->
        Members.invite(editor, album, %{"email" => "x@example.com", "role" => "editor"})
      end

      assert_raise NotAllowed, fn -> Members.list(editor, album) end
    end

    test "accepting needs the invited email", %{scope: scope, album: album} do
      invitee = user_fixture()
      {:ok, _} = Members.invite(scope, album, %{"email" => invitee.email, "role" => "editor"})
      token = invite_token()

      assert {:error, {:wrong_account, _}} = Members.accept(user_scope_fixture(), token)
      assert {:ok, joined} = Members.accept(Scope.for_user(invitee), token)
      assert joined.id == album.id
      # Used once
      assert {:error, :invalid} = Members.accept(Scope.for_user(invitee), token)
    end

    test "invitations expire after 14 days", %{scope: scope, album: album} do
      invitee = user_fixture()

      {:ok, member} =
        Members.invite(scope, album, %{"email" => invitee.email, "role" => "editor"})

      token = invite_token()

      member
      |> Ecto.Changeset.change(invited_at: DateTime.add(DateTime.utc_now(:second), -15, :day))
      |> Repo.update!()

      assert Members.get_invite(token) == nil
      assert {:error, :invalid} = Members.accept(Scope.for_user(invitee), token)
    end

    test "resending makes a new link and the old one stops", %{scope: scope, album: album} do
      invitee = user_fixture()

      {:ok, member} =
        Members.invite(scope, album, %{"email" => invitee.email, "role" => "editor"})

      old = invite_token()

      {:ok, _} = Members.resend(scope, album, member)
      new = invite_token()

      assert Members.get_invite(old) == nil
      assert Members.get_invite(new)
    end

    test "role changes, removal and leaving", %{scope: scope, album: album} do
      user = user_fixture()
      editor = join_as(scope, album, user, "editor")
      [member] = Members.list(scope, album)

      {:ok, _} = Members.change_role(scope, album, member, "viewer")
      assert Albums.role(editor, album) == :viewer

      :ok = Members.leave(editor, album)
      assert Albums.role(editor, album) == nil

      viewer = join_as(scope, album, user, "viewer")
      [member] = Members.list(scope, album)
      {:ok, _} = Members.remove(scope, album, member)
      assert Albums.role(viewer, album) == nil
    end
  end
end
