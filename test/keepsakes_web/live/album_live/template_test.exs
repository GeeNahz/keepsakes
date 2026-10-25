defmodule KeepsakesWeb.AlbumLive.TemplateTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures

  alias Keepsakes.Templates

  setup :register_and_log_in_user

  setup %{scope: scope} do
    album = album_fixture(scope, name: "Our Little One")
    guest_memory_fixture(scope, album, %{title: "First birthday"})
    %{album: album}
  end

  test "the album page links to the template picker", %{conn: conn, album: album} do
    {:ok, lv, _html} = live(conn, ~p"/albums/#{album.slug}")
    assert has_element?(lv, ~s(#album-template[href="/albums/#{album.slug}/template"]))
  end

  test "lists templates with previews, the current one and Coming soon", %{
    conn: conn,
    album: album
  } do
    {:ok, lv, _html} = live(conn, ~p"/albums/#{album.slug}/template")

    assert has_element?(lv, "#template-trail", "In use")
    refute has_element?(lv, "#use-trail")
    assert has_element?(lv, "#template-daylight")
    assert has_element?(lv, ~s(#template-daylight [style*="--color-ks-guest: #F7F3EC"]))

    assert has_element?(
             lv,
             ~s(#preview-daylight[href="/a/preview/#{album.slug}/daylight/timeline"])
           )

    assert has_element?(lv, "#create-template", "Coming soon")
    assert has_element?(lv, "#create-template-button[disabled]")
  end

  test "using a template switches the album", %{conn: conn, scope: scope, album: album} do
    {:ok, lv, _html} = live(conn, ~p"/albums/#{album.slug}/template")

    lv |> element("#use-daylight") |> render_click()

    assert has_element?(lv, "#template-daylight", "In use")
    assert has_element?(lv, "#use-trail")

    assert Templates.for_album(Keepsakes.Albums.get_album_by_slug!(scope, album.slug)).slug ==
             "daylight"
  end

  test "another user's private template can't be used", %{conn: conn, album: album} do
    template_fixture(%{slug: "theirs"}, user_fixture())
    {:ok, lv, _html} = live(conn, ~p"/albums/#{album.slug}/template")

    refute has_element?(lv, "#template-theirs")
    assert render_click(lv, "use", %{"slug" => "theirs"}) =~ "isn&#39;t available"
  end

  describe "guest pages use the album's template" do
    test "the preview in another template carries its theme", %{conn: conn, album: album} do
      html = conn |> get(~p"/a/preview/#{album.slug}/daylight/timeline") |> html_response(200)
      assert html =~ ~s(--color-ks-guest: #F7F3EC)
      assert html =~ ~s(<meta name="color-scheme" content="light">)

      {:ok, lv, _html} = live(conn, ~p"/a/preview/#{album.slug}/daylight/timeline")
      assert has_element?(lv, "#owner-preview-banner", "in Daylight")
      assert has_element?(lv, ~s(#banner-templates[href="/albums/#{album.slug}/template"]))

      assert has_element?(
               lv,
               ~s(#play-slideshow[href="/a/preview/#{album.slug}/daylight/slideshow"])
             )
    end

    test "an unknown template goes back to the picker", %{conn: conn, album: album} do
      assert {:error, {:redirect, %{to: to}}} =
               live(conn, ~p"/a/preview/#{album.slug}/nope/timeline")

      assert to == "/albums/#{album.slug}/template"
    end

    # A fresh conn: the logged-in owner would skip the code page
    test "shared links render with the chosen template", %{scope: scope, album: album} do
      link = share_link_fixture(scope, album)
      html = build_conn() |> get(~p"/a/#{link.slug}") |> html_response(200)
      refute html =~ "--color-ks-guest:"

      {:ok, _} =
        Templates.set_album_template(scope, album, Templates.get_template(scope, "daylight"))

      html = build_conn() |> get(~p"/a/#{link.slug}") |> html_response(200)
      assert html =~ ~s(--color-ks-guest: #F7F3EC)
    end
  end
end
