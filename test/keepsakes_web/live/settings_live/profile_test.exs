defmodule KeepsakesWeb.SettingsLive.ProfileTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AlbumsFixtures

  alias Keepsakes.{Accounts, Storage}

  setup :register_and_log_in_user

  test "/app/settings opens on Profile", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/app/settings")) == ~p"/app/settings/profile"
  end

  test "saves name and bio, and the avatar menu follows", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/app/settings/profile")

    lv
    |> form("#profile-form",
      user: %{first_name: "Grace", last_name: "Hopper", bio: "  Mum of two  "}
    )
    |> render_submit()

    user = Accounts.get_user!(user.id)
    assert {Accounts.User.full_name(user), user.bio} == {"Grace Hopper", "Mum of two"}
    assert has_element?(lv, ~s(#user-menu-button [aria-label="Grace Hopper"]))
  end

  test "requires a first name", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/app/settings/profile")
    result = lv |> form("#profile-form", user: %{first_name: ""}) |> render_submit()
    assert result =~ "can&#39;t be blank"
  end

  test "uploads a square profile photo and can remove it", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/app/settings/profile")

    photo =
      file_input(lv, "#avatar-form", :avatar, [
        %{name: "me.jpg", content: jpeg(width: 900, height: 600), type: "image/jpeg"}
      ])

    render_upload(photo, "me.jpg")

    user = Accounts.get_user!(user.id)
    assert user.avatar_key =~ ~r{^users/#{user.id}/avatar/.+\.webp$}
    {:ok, data} = Storage.get(user.avatar_key)
    {:ok, image} = Image.from_binary(data)
    assert {Image.width(image), Image.height(image)} == {256, 256}
    assert has_element?(lv, "#user-menu-button img")

    lv |> element("#remove-avatar") |> render_click()
    assert is_nil(Accounts.get_user!(user.id).avatar_key)
    refute Storage.exists?(user.avatar_key)
  end
end
