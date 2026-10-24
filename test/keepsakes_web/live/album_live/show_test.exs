defmodule KeepsakesWeb.AlbumLive.ShowTest do
  use KeepsakesWeb.ConnCase, async: true
  use Oban.Testing, repo: Keepsakes.Repo

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures

  alias Keepsakes.Albums
  alias Keepsakes.Media.ProcessMemory

  setup :register_and_log_in_user

  setup %{scope: scope} do
    %{album: album_fixture(scope, name: "Our Little One")}
  end

  defp upload(lv, files) do
    entries =
      for {name, binary} <- files,
          do: %{name: name, content: binary, type: "image/jpeg", last_modified: 1_700_000_000_000}

    input = file_input(lv, "#upload-form", :photos, entries)
    for {name, _} <- files, do: render_upload(input, name)
    input
  end

  describe "album page" do
    test "no photos: drop zone, placeholders and share disabled", %{conn: conn, album: album} do
      {:ok, lv, _html} = live(conn, ~p"/albums/#{album.slug}")

      assert has_element?(lv, "#album-title", "Our Little One")
      assert has_element?(lv, "#album-subtitle", "No memories yet")
      assert has_element?(lv, "#drop-zone")
      assert has_element?(lv, ~s(#drop-upload-one[for]))
      assert has_element?(lv, "#share-album[disabled]")
      refute has_element?(lv, "#memories")
    end

    test "grid in timeline order with cover badge and subtitle", %{
      conn: conn,
      scope: scope,
      album: album
    } do
      later = memory_fixture(scope, album, %{title: "Christmas morning", month: 12, year: 2021})
      earlier = memory_fixture(scope, album, %{title: "First birthday", month: 4, year: 2019})
      {:ok, _} = Albums.set_cover(scope, Keepsakes.Repo.reload!(album), earlier)

      {:ok, lv, html} = live(conn, ~p"/albums/#{album.slug}")

      assert has_element?(
               lv,
               "#album-subtitle",
               "2 memories · Apr 2019 – Dec 2021 · Sorted by date taken"
             )

      assert has_element?(lv, "#memories-#{earlier.id}", "Cover")
      refute has_element?(lv, "#memories-#{later.id}", "Cover")
      assert html =~ ~r/First birthday.*Christmas morning/s
      assert has_element?(lv, "#upload-bar")
      assert has_element?(lv, "#sidebar-album-#{album.id}", "2")
    end

    test "incomplete memories are flagged", %{conn: conn, scope: scope, album: album} do
      memory = memory_fixture(scope, album, %{title: "Beach day"})
      {:ok, lv, _html} = live(conn, ~p"/albums/#{album.slug}")

      assert has_element?(lv, "#memories-#{memory.id}", "Needs date")
    end

    test "another owner's album is not found", %{conn: conn} do
      other = album_fixture(user_scope_fixture(), name: "Private")

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/albums/#{other.slug}") end
    end

    test "New album dialog creates an album", %{conn: conn, album: album} do
      {:ok, lv, _html} = live(conn, ~p"/albums/#{album.slug}")
      assert has_element?(lv, "#sidebar-new-album")

      assert lv |> form("#new-album-form", album: %{name: " "}) |> render_submit() =~
               "Give your album a name"

      {:ok, _lv, html} =
        lv
        |> form("#new-album-form", album: %{name: "Lagos Trip 2023", description: "Sun"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/albums/lagos-trip-2023")

      assert html =~ "Lagos Trip 2023"
    end
  end

  describe "uploading" do
    test "a picked photo opens the upload screen as a draft", %{conn: conn, album: album} do
      {:ok, lv, _html} = live(conn, ~p"/albums/#{album.slug}")

      upload(lv, [{"IMG_2041.jpg", jpeg(taken: "2019:04:12 10:00:00")}])
      assert_patch(lv, ~p"/albums/#{album.slug}/upload")

      assert [draft] = Albums.list_drafts(scope_of(conn), album)
      assert draft.original_filename == "IMG_2041.jpg"
      assert has_element?(lv, "#upload-title", "Add a memory")
      assert has_element?(lv, "#queue-#{draft.id}[aria-pressed=true]", "Needs name + date")
      assert has_element?(lv, "#optimise-note", "Optimising IMG_2041.jpg")
      assert has_element?(lv, "#upload-save[disabled]")

      # Processing finishes: EXIF date fills in live
      :ok = perform_job(ProcessMemory, %{memory_id: draft.id})
      assert has_element?(lv, "#optimise-note", "IMG_2041.jpg optimised")
      assert has_element?(lv, ~s(#memory-month option[value="4"][selected]))
      assert has_element?(lv, ~s(#memory-year option[value="2019"][selected]))
    end

    test "filling the form makes it ready and saving publishes it", %{conn: conn, album: album} do
      {:ok, lv, _html} = live(conn, ~p"/albums/#{album.slug}/upload")
      assert has_element?(lv, "#drop-zone")

      upload(lv, [{"IMG_1.jpg", jpeg()}])
      [draft] = Albums.list_drafts(scope_of(conn), album)

      lv
      |> form("#memory-form",
        memory: %{title: "First birthday", month: "4", year: "2019", caption: "Fun"}
      )
      |> render_change()

      assert has_element?(lv, "#queue-#{draft.id}", "Ready")
      assert has_element?(lv, "#upload-status", "under April 2019")

      lv |> form("#people-form") |> render_submit(%{person: "Ada"})
      lv |> form("#people-form") |> render_submit(%{person: "Mum"})
      lv |> element(~s(#memory-people button[aria-label="Remove Mum"])) |> render_click()
      assert Albums.get_memory!(scope_of(conn), draft.id).people == ["Ada"]

      lv |> element("#upload-save") |> render_click()
      assert_patch(lv, ~p"/albums/#{album.slug}")

      assert has_element?(lv, "#memories-#{draft.id}", "First birthday")
      assert has_element?(lv, "#memories-#{draft.id}", "Cover")
      assert Albums.list_drafts(scope_of(conn), album) == []
    end

    test "bulk: counter, prev/next and publishing incomplete photos", %{conn: conn, album: album} do
      {:ok, lv, _html} = live(conn, ~p"/albums/#{album.slug}/upload")
      upload(lv, [{"a.jpg", jpeg()}, {"b.jpg", jpeg()}, {"c.jpg", jpeg()}])

      [first, second, third] = Albums.list_drafts(scope_of(conn), album)
      assert has_element?(lv, "#upload-title", "Review 3 photos before uploading")
      assert has_element?(lv, "#memory-counter", "Photo 1 of 3")

      lv |> element("#memory-next") |> render_click()
      assert has_element?(lv, "#queue-#{second.id}[aria-pressed=true]")
      lv |> element("#memory-prev") |> render_click()
      lv |> element("#memory-prev") |> render_click()
      assert has_element?(lv, "#queue-#{third.id}[aria-pressed=true]")
      lv |> element("#queue-#{first.id}") |> render_click()
      assert has_element?(lv, "#memory-counter", "Photo 1 of 3")

      assert has_element?(lv, "#upload-status", "3 photos still need a name or date")
      refute has_element?(lv, "#upload-save[disabled]")
      assert has_element?(lv, "#upload-save", "Upload 3 photos")

      lv |> element("#upload-save") |> render_click()
      assert_patch(lv, ~p"/albums/#{album.slug}")
      assert has_element?(lv, "#memories-#{third.id}", "Needs name + date")
    end

    test "cancel deletes the drafts", %{conn: conn, album: album} do
      {:ok, lv, _html} = live(conn, ~p"/albums/#{album.slug}/upload")
      upload(lv, [{"a.jpg", jpeg()}])

      lv |> element("#upload-cancel") |> render_click()
      assert_patch(lv, ~p"/albums/#{album.slug}")
      assert Albums.list_drafts(scope_of(conn), album) == []
    end

    test "drafts left behind can be resumed", %{conn: conn, scope: scope, album: album} do
      draft_fixture(scope, album)
      {:ok, lv, _html} = live(conn, ~p"/albums/#{album.slug}")

      lv |> element("#resume-upload") |> render_click()
      assert_patch(lv, ~p"/albums/#{album.slug}/upload")
      assert has_element?(lv, "#memory-form")
    end

    test "rejects files that aren't photos", %{conn: conn, album: album} do
      {:ok, lv, _html} = live(conn, ~p"/albums/#{album.slug}/upload")

      input =
        file_input(lv, "#upload-form", :photos, [
          %{name: "notes.txt", content: "hello", type: "text/plain"}
        ])

      assert {:error, [[_ref, :not_accepted]]} = render_upload(input, "notes.txt")
    end
  end

  describe "editing a memory" do
    test "edit dialog saves, sets cover and deletes", %{conn: conn, scope: scope, album: album} do
      one = memory_fixture(scope, album, %{title: "One", month: 1, year: 2020})
      two = memory_fixture(scope, album, %{title: "Two", month: 2, year: 2020})

      {:ok, lv, _html} = live(conn, ~p"/albums/#{album.slug}")
      lv |> element("#memories-#{two.id}") |> render_click()
      assert_patch(lv, ~p"/albums/#{album.slug}/memories/#{two.id}")
      assert has_element?(lv, "#edit-memory-dialog")

      lv |> form("#memory-form", memory: %{title: "Second", cover: "true"}) |> render_change()
      assert has_element?(lv, "#memories-#{two.id}", "Second")
      assert has_element?(lv, "#memories-#{two.id}", "Cover")
      refute has_element?(lv, "#memories-#{one.id}", "Cover")

      lv |> element("#delete-memory") |> render_click()
      assert_patch(lv, ~p"/albums/#{album.slug}")
      refute has_element?(lv, "#memories-#{two.id}")
      assert has_element?(lv, "#album-subtitle", "1 memory")
    end

    test "can't open another album's memory", %{conn: conn, scope: scope, album: album} do
      other = memory_fixture(scope, album_fixture(scope), %{title: "Elsewhere"})

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/albums/#{album.slug}/memories/#{other.id}")
      end
    end
  end

  defp scope_of(conn) do
    token = Plug.Conn.get_session(conn, :user_token)
    {user, _} = Keepsakes.Accounts.get_user_by_session_token(token)
    Keepsakes.Accounts.Scope.for_user(user)
  end
end
