defmodule Keepsakes.TemplatesTest do
  use Keepsakes.DataCase, async: true

  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures

  alias Keepsakes.{Repo, Templates}
  alias Keepsakes.Templates.{Template, Theme}

  setup do
    %{scope: user_scope_fixture()}
  end

  describe "seeded templates" do
    test "Trail and Daylight are listed in order, Trail is the system default", %{scope: scope} do
      assert ["trail", "daylight"] = scope |> Templates.list_templates() |> Enum.map(& &1.slug)
      assert Templates.system_default().slug == "trail"
    end

    test "every template's renderer is drawable" do
      for template <- Repo.all(Template) do
        assert template.renderer in Templates.renderers()
        assert KeepsakesWeb.Templates.renderer(template)
      end
    end
  end

  describe "albums" do
    test "new albums get the owner's default, else the system default", %{scope: scope} do
      assert album_fixture(scope).template_id == Templates.system_default().id

      daylight = Templates.get_template(scope, "daylight")
      {:ok, user} = Templates.set_default_template(scope, daylight)
      scope = %{scope | user: user}

      assert album_fixture(scope).template_id == daylight.id
      assert Templates.default_for(scope).id == daylight.id
    end

    test "for_album falls back when the album's template is switched off", %{scope: scope} do
      private = template_fixture(%{slug: "spare", active: true})
      album = album_fixture(scope)
      {:ok, album} = album |> Ecto.Changeset.change(template_id: private.id) |> Repo.update()
      assert Templates.for_album(album).id == private.id

      {:ok, _} = private |> Ecto.Changeset.change(active: false) |> Repo.update()
      assert Templates.for_album(album).slug == "trail"

      daylight = Templates.get_template(scope, "daylight")
      {:ok, _} = Templates.set_default_template(scope, daylight)
      assert Templates.for_album(album).slug == "daylight"
    end

    test "set_album_template switches the look", %{scope: scope} do
      album = album_fixture(scope)
      daylight = Templates.get_template(scope, "daylight")

      assert {:ok, album} = Templates.set_album_template(scope, album, daylight)
      assert Templates.for_album(album).slug == "daylight"
    end

    test "another user's private template is not available", %{scope: scope} do
      other = user_scope_fixture()
      theirs = template_fixture(%{slug: "theirs"}, other.user)

      assert Templates.get_template(other, "theirs")
      refute Templates.get_template(scope, "theirs")
      refute "theirs" in Enum.map(Templates.list_templates(scope), & &1.slug)

      assert {:error, :unavailable} =
               Templates.set_album_template(scope, album_fixture(scope), theirs)

      assert {:error, :unavailable} = Templates.set_default_template(scope, theirs)
    end

    test "another owner's album can't be changed", %{scope: scope} do
      album = album_fixture(user_scope_fixture())

      assert_raise FunctionClauseError, fn ->
        Templates.set_album_template(scope, album, Templates.system_default())
      end
    end
  end

  describe "Theme" do
    test "css_vars maps slots to custom properties" do
      assert Theme.css_vars(%{"page" => "#F7F3EC", "primary" => "#1F5F5B"}) ==
               "--color-ks-guest: #F7F3EC; --color-primary: #1F5F5B"

      assert Theme.css_vars(%{"hand_font" => "DM Sans"}) =~ ~s(--font-hand: "DM Sans")
      assert Theme.css_vars(%{}) == ""
    end

    test "invalid values are reported and never emitted" do
      theme = %{
        "page" => "red; background: url(x)",
        "ink" => "#FFF",
        "hand_font" => "Comic Sans",
        "glow" => "#FFFFFF",
        "text" => "#B8BDC8"
      }

      assert theme |> Theme.errors() |> Enum.map(&elem(&1, 0)) |> Enum.sort() ==
               ["glow", "hand_font", "ink", "page"]

      assert Theme.css_vars(theme) == "--color-ks-guest-text: #B8BDC8"
    end

    test "scheme defaults to dark" do
      assert Theme.scheme(%{}) == "dark"
      assert Theme.scheme(%{"scheme" => "light"}) == "light"
    end

    test "the changeset rejects a bad theme" do
      changeset =
        Template.changeset(%Template{}, %{slug: "x", name: "X", theme: %{"page" => "nope"}})

      assert %{theme: ["page must be a colour like #1F5F5B"]} = errors_on(changeset)
    end
  end
end
