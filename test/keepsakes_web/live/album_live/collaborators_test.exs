defmodule KeepsakesWeb.AlbumLive.CollaboratorsTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures
  import Keepsakes.BillingFixtures

  alias Keepsakes.Accounts.Scope
  alias Keepsakes.Albums.{Member, Members}
  alias Keepsakes.Repo

  setup :register_and_log_in_user

  setup %{user: user, scope: scope} do
    put_on_plan(user, "plus")
    %{album: album_fixture(scope, name: "Our Little One")}
  end

  defp member(album, owner, role) do
    user = user_fixture(%{first_name: "Chidi"})

    Repo.insert!(%Member{
      album_id: album.id,
      user_id: user.id,
      invited_by_id: owner.id,
      email: user.email,
      role: role,
      invited_at: DateTime.utc_now(:second),
      accepted_at: DateTime.utc_now(:second)
    })

    user
  end

  describe "people page" do
    test "invites by email and lists pending people", %{conn: conn, album: album} do
      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}/people")
      assert has_element?(lv, "#people-empty")
      assert has_element?(lv, "#people-seats", "0 of 2")

      lv
      |> form("#invite-form", member: %{email: "aunt@example.com", role: "viewer"})
      |> render_submit()

      assert has_element?(lv, "#people-list", "aunt@example.com")
      assert has_element?(lv, "#people-list", "invitation sent")
      assert has_element?(lv, "#people-seats", "1 of 2")
    end

    test "shows form errors and the seat limit", %{
      conn: conn,
      user: user,
      scope: scope,
      album: album
    } do
      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}/people")

      lv |> form("#invite-form", member: %{email: user.email, role: "editor"}) |> render_submit()
      assert has_element?(lv, "#invite-form", "is your own account")

      {:ok, _} = Members.invite(scope, album, %{"email" => "a@example.com", "role" => "editor"})
      {:ok, _} = Members.invite(scope, album, %{"email" => "b@example.com", "role" => "editor"})

      lv
      |> form("#invite-form", member: %{email: "c@example.com", role: "editor"})
      |> render_submit()

      assert has_element?(lv, "#invite-limit", "all 2 collaborator seats")
    end

    test "Free plans see an upgrade prompt", %{conn: conn, user: user, album: album} do
      put_on_plan(user, "free")
      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}/people")
      assert has_element?(lv, "#people-upgrade")
      refute has_element?(lv, "#invite-form")
    end

    test "changes roles and removes people", %{conn: conn, user: user, album: album} do
      chidi = member(album, user, "editor")
      [m] = Repo.all(Member)
      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}/people")

      lv |> form("#member-role-#{m.id}") |> render_change(%{member_id: m.id, role: "viewer"})
      assert Repo.reload!(m).role == "viewer"

      lv |> element("#member-remove-#{m.id}") |> render_click()
      refute has_element?(lv, "#member-#{m.id}")
      assert Keepsakes.Albums.role(Scope.for_user(chidi), album) == nil
    end

    test "is the owner's only", %{album: album, user: user} do
      editor = member(album, user, "editor")
      conn = log_in_user(build_conn(), editor)

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/app/albums/#{album.slug}/people") end
    end
  end

  describe "a collaborator's album page" do
    test "editors see uploads and the editor, but no owner actions", %{
      scope: scope,
      user: user,
      album: album
    } do
      memory = memory_fixture(scope, album, %{title: "Beach", month: 4, year: 2020})
      editor = member(album, user, "editor")
      conn = log_in_user(build_conn(), editor)

      {:ok, lv, _html} = live(conn, ~p"/app/shared/#{album.id}")
      assert has_element?(lv, "#album-shared-by", "an editor")
      assert has_element?(lv, "#upload-bar")
      assert has_element?(lv, ~s(a[href="/app/shared/#{album.id}/memories/#{memory.id}"]))
      refute has_element?(lv, "#share-album")
      refute has_element?(lv, "#album-people")
      assert has_element?(lv, "#sidebar-shared-#{album.id}")
    end

    test "viewers only look", %{scope: scope, user: user, album: album} do
      memory = memory_fixture(scope, album, %{title: "Beach", month: 4, year: 2020})
      viewer = member(album, user, "viewer")
      conn = log_in_user(build_conn(), viewer)

      {:ok, lv, _html} = live(conn, ~p"/app/shared/#{album.id}")
      assert has_element?(lv, "#album-shared-by", "a viewer")
      assert has_element?(lv, "#memories", "Beach")
      refute has_element?(lv, "#upload-bar")
      refute has_element?(lv, ~s(a[href="/app/shared/#{album.id}/memories/#{memory.id}"]))

      assert_raise Keepsakes.Albums.NotAllowed, fn ->
        live(conn, ~p"/app/shared/#{album.id}/memories/#{memory.id}")
      end
    end

    test "strangers get nothing", %{album: album} do
      conn = log_in_user(build_conn(), user_fixture())
      assert_raise Keepsakes.Albums.NotAllowed, fn -> live(conn, ~p"/app/shared/#{album.id}") end
    end

    test "leaving the album", %{user: user, album: album} do
      viewer = member(album, user, "viewer")
      conn = log_in_user(build_conn(), viewer)
      {:ok, lv, _html} = live(conn, ~p"/app/shared/#{album.id}")

      assert {:error, {:live_redirect, %{to: "/app/albums"}}} =
               lv |> element("#leave-album") |> render_click()

      assert Repo.all(Member) == []
    end
  end

  describe "invitation links" do
    setup %{scope: scope, album: album} do
      invitee = user_fixture()
      {:ok, _} = Members.invite(scope, album, %{"email" => invitee.email, "role" => "editor"})

      token =
        receive_invite_token()

      %{invitee: invitee, token: token}
    end

    defp receive_invite_token do
      receive do
        {:email, %Swoosh.Email{text_body: body}} ->
          case Regex.run(~r{/invites/([\w-]+)}, body) do
            [_, token] -> token
            nil -> receive_invite_token()
          end
      after
        1000 -> flunk("no invitation email")
      end
    end

    test "signed out: sign in first, then come back", %{token: token} do
      conn = get(build_conn(), ~p"/invites/#{token}")
      assert html_response(conn, 200) =~ "Join Our Little One"
      assert get_session(conn, :user_return_to) == "/invites/#{token}"
    end

    test "the invited account joins with the button", %{
      invitee: invitee,
      token: token,
      album: album
    } do
      conn = log_in_user(build_conn(), invitee)
      assert html_response(get(conn, ~p"/invites/#{token}"), 200) =~ "invite-accept"

      conn = post(conn, ~p"/invites/#{token}")
      assert redirected_to(conn) == "/app/shared/#{album.id}"
    end

    test "another account is told it's for someone else", %{token: token} do
      conn = log_in_user(build_conn(), user_fixture())
      assert html_response(get(conn, ~p"/invites/#{token}"), 200) =~ "invite-wrong-account"
    end

    test "unknown links say they've expired" do
      assert html_response(get(build_conn(), ~p"/invites/nope"), 200) =~ "invite-invalid"
    end
  end
end
