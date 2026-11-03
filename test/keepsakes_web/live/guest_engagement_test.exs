defmodule KeepsakesWeb.GuestEngagementTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures
  import Keepsakes.BillingFixtures

  alias Keepsakes.Accounts.Scope
  alias Keepsakes.{Albums, Music, Repo}
  alias Keepsakes.Sharing.Engagement

  setup do
    owner = user_fixture(%{first_name: "Ngozi"})
    put_on_plan(owner, "plus")

    for f <- [:guest_uploads, :reactions_guestbook, :slideshow_music],
        do: FunWithFlags.enable(f, for_actor: owner)

    scope = Scope.for_user(owner)
    album = album_fixture(scope, name: "Our Little One")
    memory = guest_memory_fixture(scope, album, %{title: "Beach day", caption: "Waves"})
    link = share_link_fixture(scope, album)
    %{owner: owner, scope: scope, album: album, memory: memory, link: link}
  end

  defp as_guest(conn, link, key \\ "visitor-1"),
    do:
      init_test_session(conn, %{
        "guest_links" => %{link.id => link.code_version},
        "guest_visitor" => key
      })

  defp turn_on(scope, link, attrs) do
    {:ok, link} = Engagement.update_features(scope, link, attrs)
    link
  end

  describe "hearts on the timeline" do
    test "show only when turned on", %{conn: conn, link: link, memory: memory} do
      {:ok, lv, _html} = live(as_guest(conn, link), ~p"/a/#{link.slug}/timeline")
      refute has_element?(lv, "#heart-#{memory.id}")
      refute has_element?(lv, "#guestbook-link")
    end

    test "a guest hearts and un-hearts a photo", %{
      conn: conn,
      scope: scope,
      link: link,
      memory: memory
    } do
      link = turn_on(scope, link, %{"reactions_guestbook" => "true"})
      {:ok, lv, _html} = live(as_guest(conn, link), ~p"/a/#{link.slug}/timeline")
      assert has_element?(lv, "#guestbook-link")

      lv |> element("#heart-#{memory.id}") |> render_click()
      assert has_element?(lv, ~s(#heart-#{memory.id}[aria-pressed="true"]), "1")

      lv |> element("#heart-#{memory.id}") |> render_click()
      assert has_element?(lv, ~s(#heart-#{memory.id}[aria-pressed="false"]))
    end

    test "other guests' hearts arrive live", %{
      conn: conn,
      scope: scope,
      link: link,
      memory: memory
    } do
      link = turn_on(scope, link, %{"reactions_guestbook" => "true"})
      {:ok, lv, _html} = live(as_guest(conn, link), ~p"/a/#{link.slug}/timeline")

      {:ok, true, 1} =
        Engagement.toggle_heart(Repo.preload(link, [:album, :user]), "someone", memory.id)

      assert render(lv) =~ ~s(aria-label="Leave a heart")
      assert has_element?(lv, "#heart-#{memory.id}", "1")
    end
  end

  describe "guestbook page" do
    test "sign, see it pending, then approved", %{
      conn: conn,
      scope: scope,
      album: album,
      link: link
    } do
      link = turn_on(scope, link, %{"reactions_guestbook" => "true"})
      {:ok, lv, _html} = live(as_guest(conn, link), ~p"/a/#{link.slug}/guestbook")
      assert has_element?(lv, "#guestbook-empty")

      lv
      |> form("#guestbook-form", guestbook_entry: %{name: "Bisi", message: "So lovely!"})
      |> render_submit()

      assert has_element?(lv, "#guestbook-notes", "Waiting for approval")

      [note] = Engagement.pending_notes(scope, album)
      {:ok, _} = Engagement.approve_note(scope, album, note.id)
      refute has_element?(lv, "#guestbook-notes", "Waiting for approval")
      assert has_element?(lv, "#guestbook-note-#{note.id}", "So lovely!")
    end

    test "is closed unless turned on", %{conn: conn, link: link} do
      assert {:error, {:live_redirect, %{to: to}}} =
               live(as_guest(conn, link), ~p"/a/#{link.slug}/guestbook")

      assert to == "/a/#{link.slug}/timeline"
    end
  end

  describe "add photos page" do
    test "sends photos for approval with the guest's name", %{
      conn: conn,
      scope: scope,
      album: album,
      link: link
    } do
      link = turn_on(scope, link, %{"guest_uploads" => "true"})
      {:ok, lv, _html} = live(as_guest(conn, link), ~p"/a/#{link.slug}/add")

      photos =
        file_input(lv, "#add-form", :photos, [
          %{name: "cake.jpg", content: jpeg(), type: "image/jpeg"}
        ])

      render_upload(photos, "cake.jpg")

      lv
      |> form("#add-form", guest: %{guest_name: "Aunt Bisi", title: "Cake", rights: "true"})
      |> render_submit()

      assert has_element?(lv, "#add-done", "sent for approval")

      assert [%{guest_name: "Aunt Bisi", title: "Cake", status: "submitted"}] =
               Albums.list_submitted(scope, album)
    end

    test "the rights box is required", %{conn: conn, scope: scope, album: album, link: link} do
      link = turn_on(scope, link, %{"guest_uploads" => "true"})
      {:ok, lv, _html} = live(as_guest(conn, link), ~p"/a/#{link.slug}/add")

      photos =
        file_input(lv, "#add-form", :photos, [
          %{name: "cake.jpg", content: jpeg(), type: "image/jpeg"}
        ])

      render_upload(photos, "cake.jpg")
      lv |> form("#add-form", guest: %{guest_name: "Bisi", rights: "false"}) |> render_submit()

      assert has_element?(lv, "#add-error", "confirm")
      assert Albums.list_submitted(scope, album) == []
    end

    test "needs the code and the switch", %{conn: conn, scope: scope, link: link} do
      assert {:error, {:live_redirect, _}} = live(as_guest(conn, link), ~p"/a/#{link.slug}/add")

      link = turn_on(scope, link, %{"guest_uploads" => "true"})
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/a/#{link.slug}/add")
      assert to == "/a/#{link.slug}"
    end

    test "the owner reviews them on the album page", %{scope: scope, album: album, link: link} do
      link =
        turn_on(scope, link, %{"guest_uploads" => "true"})
        |> Repo.preload([:album, :user], force: true)

      path = Path.join(System.tmp_dir!(), "g-#{System.unique_integer([:positive])}.jpg")
      File.write!(path, jpeg())

      {:ok, photo} =
        Engagement.add_photo(
          link,
          "v",
          %{path: path, filename: "g.jpg", bytes: File.stat!(path).size},
          %{
            guest_name: "Bisi",
            title: "Cake"
          }
        )

      conn = log_in_user(build_conn(), scope.user)
      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}")
      assert has_element?(lv, "#review-photos", "1 guest photo")

      lv |> element("#approve-photo-#{photo.id}") |> render_click()
      refute has_element?(lv, "#review-queue")
      assert has_element?(lv, "#memories", "Added by Bisi")
    end
  end

  describe "time capsule" do
    test "a sealed album shows the countdown, never the photos", %{
      conn: conn,
      scope: scope,
      album: album,
      link: link
    } do
      {:ok, _} = Albums.set_reveal(scope, album, DateTime.add(DateTime.utc_now(), 30, :day))

      {:ok, lv, html} = live(as_guest(conn, link), ~p"/a/#{link.slug}/timeline")
      assert has_element?(lv, "#album-sealed")
      assert has_element?(lv, "#sealed-countdown")
      refute html =~ "Beach day"
    end

    test "a sealed memory is a placeholder", %{
      conn: conn,
      scope: scope,
      memory: memory,
      link: link
    } do
      {:ok, _} =
        Albums.set_memory_reveal(scope, memory, DateTime.add(DateTime.utc_now(), 30, :day))

      {:ok, lv, html} = live(as_guest(conn, link), ~p"/a/#{link.slug}/timeline")
      assert has_element?(lv, "#sealed-#{memory.id}", "Opens on")
      refute html =~ "Beach day"
      refute html =~ "Waves"

      {:ok, _lv, html} = live(as_guest(conn, link), ~p"/a/#{link.slug}/slideshow")
      refute html =~ "Beach day"
    end

    test "the owner always sees through it", %{scope: scope, album: album, link: link} do
      {:ok, _} = Albums.set_reveal(scope, album, DateTime.add(DateTime.utc_now(), 30, :day))
      conn = log_in_user(build_conn(), scope.user)

      {:ok, lv, _html} = live(conn, ~p"/a/#{link.slug}/timeline")
      refute has_element?(lv, "#album-sealed")
      assert render(lv) =~ "Beach day"
    end
  end

  describe "slideshow music" do
    test "plays the album's track when the link allows it", %{
      conn: conn,
      scope: scope,
      album: album,
      link: link
    } do
      path = Path.join(System.tmp_dir!(), "m-#{System.unique_integer([:positive])}.mp3")
      File.write!(path, <<"ID3", 4, 0, 0, 0, 0, 0, 0>> <> :binary.copy(<<0>>, 500))
      {:ok, _} = Music.upload(scope, album, %{path: path, filename: "song.mp3", bytes: 510})

      {:ok, lv, _html} = live(as_guest(conn, link), ~p"/a/#{link.slug}/slideshow")
      refute has_element?(lv, "#slideshow-music")

      link = turn_on(scope, link, %{"slideshow_music" => "true"})
      {:ok, lv, _html} = live(as_guest(conn, link), ~p"/a/#{link.slug}/slideshow")
      assert has_element?(lv, "#slideshow-music audio[src]")
    end
  end

  describe "share page" do
    setup %{scope: scope} do
      %{conn: log_in_user(build_conn(), scope.user)}
    end

    test "turns guest features on", %{conn: conn, album: album, link: link} do
      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}/share")

      lv
      |> form("#share-features-form",
        share_link: %{guest_uploads: "true", reactions_guestbook: "true"}
      )
      |> render_change()

      link = Repo.reload!(link)
      assert link.guest_uploads and link.reactions_guestbook
      assert has_element?(lv, "#print-qr-card")
      assert has_element?(lv, "#share-music")
      assert has_element?(lv, "#album-reveal-form")
    end

    test "seals the album from the time capsule form", %{conn: conn, album: album} do
      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}/share")
      at = DateTime.utc_now() |> DateTime.add(10, :day) |> Calendar.strftime("%Y-%m-%dT%H:%M")

      lv |> form("#album-reveal-form", reveal: %{at: at, offset: "0"}) |> render_submit()
      assert Repo.reload!(album).reveal_at
      assert has_element?(lv, "#album-reveal-form-state", "Sealed until")

      lv |> element("#album-reveal-form-open") |> render_click()
      refute Repo.reload!(album).reveal_at
    end

    test "features the plan lacks show as upgrades", %{conn: conn, owner: owner, album: album} do
      put_on_plan(owner, "free")
      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}/share")
      assert has_element?(lv, "#share_link_guest_uploads[disabled]")
      assert has_element?(lv, "#time-capsule-upgrade")
      refute has_element?(lv, "#share-music")
    end

    test "the QR card and its PNG", %{conn: conn, album: album, link: link} do
      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}/share/card")
      assert has_element?(lv, "#qr-card svg")
      refute has_element?(lv, "#qr-card", "482917")

      lv |> form("#card-options", %{show_code: "true"}) |> render_change()
      assert has_element?(lv, "#qr-card", "482917")
      assert link.slug

      conn = get(conn, ~p"/app/albums/#{album.slug}/share/qr.png")
      assert get_resp_header(conn, "content-type") == ["image/png"]
      assert <<137, "PNG", _::binary>> = conn.resp_body
    end
  end
end
