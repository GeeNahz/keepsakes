defmodule Keepsakes.PlatformAdminTest do
  use Keepsakes.DataCase, async: true

  import Keepsakes.AccountsFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.{Audit, Flags, Templates}
  alias Keepsakes.Staff.Forbidden
  alias Keepsakes.Templates.Admin, as: TemplatesAdmin

  setup do
    %{admin: staff_scope_fixture()}
  end

  describe "templates" do
    test "creates a template with a theme, empty colours dropped", %{admin: admin} do
      assert {:ok, t} =
               TemplatesAdmin.create(admin, %{
                 "name" => "Meadow",
                 "slug" => "meadow",
                 "renderer" => "trail",
                 "active" => "true",
                 "theme" => %{
                   "page" => "#F7F3EC",
                   "ink" => "",
                   "scheme" => "light",
                   "display_font" => "Caveat"
                 }
               })

      assert t.theme == %{"page" => "#F7F3EC", "scheme" => "light", "display_font" => "Caveat"}
      assert [%{action: "template.created"}] = Audit.list(admin, %{"action" => "template."})
    end

    test "rejects a bad colour", %{admin: admin} do
      assert {:error, changeset} =
               TemplatesAdmin.create(admin, %{
                 "name" => "X",
                 "slug" => "x",
                 "theme" => %{"page" => "red"}
               })

      assert errors_on(changeset)[:theme]
    end

    test "the system default can't be hidden; others can", %{admin: admin} do
      default = Templates.system_default()
      assert {:error, changeset} = TemplatesAdmin.update(admin, default, %{"active" => "false"})
      assert errors_on(changeset)[:active]

      {:ok, other} =
        TemplatesAdmin.create(admin, %{"name" => "Other", "slug" => "other", "active" => "true"})

      assert {:ok, %{active: false}} = TemplatesAdmin.update(admin, other, %{"active" => "false"})
    end

    test "slugs don't change after creation", %{admin: admin} do
      {:ok, t} = TemplatesAdmin.create(admin, %{"name" => "Fixed", "slug" => "fixed"})
      {:ok, t} = TemplatesAdmin.update(admin, t, %{"slug" => "renamed", "name" => "Fixed 2"})
      assert t.slug == "fixed"
      assert t.name == "Fixed 2"
    end

    test "need templates.manage" do
      assert_raise Forbidden, fn -> TemplatesAdmin.list(staff_scope_fixture(["support"])) end
    end
  end

  describe "feature flags" do
    test "off, chosen customers, everyone", %{admin: admin} do
      ada = user_fixture()
      bola = user_fixture()

      assert {:off, []} = Flags.state(:guest_uploads)
      refute Flags.enabled?(:guest_uploads, ada)

      assert {:ok, _} = Flags.add_customer(admin, :guest_uploads, ada.email)
      :ok = Flags.set(admin, :guest_uploads, :chosen)
      assert {:chosen, [%{id: id}]} = Flags.state(:guest_uploads)
      assert id == ada.id
      assert Flags.enabled?(:guest_uploads, ada)
      refute Flags.enabled?(:guest_uploads, bola)

      :ok = Flags.set(admin, :guest_uploads, :everyone)
      assert Flags.enabled?(:guest_uploads, bola)
      assert Flags.enabled?(:guest_uploads)

      :ok = Flags.set(admin, :guest_uploads, :off)
      assert {:off, []} = Flags.state(:guest_uploads)
      refute Flags.enabled?(:guest_uploads, ada)

      assert length(Audit.list(admin, %{"action" => "flag."})) == 4
    end

    test "removing a customer and unknown emails", %{admin: admin} do
      ada = user_fixture()
      {:ok, _} = Flags.add_customer(admin, :slideshow_music, ada.email)

      assert {:error, :no_account} =
               Flags.add_customer(admin, :slideshow_music, "nobody@example.com")

      :ok = Flags.remove_customer(admin, :slideshow_music, ada)
      refute Flags.enabled?(:slideshow_music, ada)
    end

    test "only declared flags exist" do
      assert_raise FunctionClauseError, fn -> Flags.enabled?(:made_up) end
    end

    test "need flags.manage" do
      assert_raise Forbidden, fn ->
        Flags.set(staff_scope_fixture(["support"]), :guest_uploads, :everyone)
      end
    end
  end
end
