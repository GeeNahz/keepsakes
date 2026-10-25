defmodule Keepsakes.Repo.Migrations.CreateTemplates do
  use Ecto.Migration

  # Trail is the canvas design; Daylight is the same layout in a light theme.
  # Theme keys are the slots in Keepsakes.Templates.Theme.
  @templates [
    %{
      slug: "trail",
      name: "Trail",
      description: "Polaroids along a dashed trail, on a dark night background.",
      position: 1,
      theme: %{}
    },
    %{
      slug: "daylight",
      name: "Daylight",
      description: "The same trail on warm paper, with teal accents.",
      position: 2,
      theme: %{
        "scheme" => "light",
        "page" => "#F7F3EC",
        "ink" => "#1B1E27",
        "text" => "#5A6070",
        "card" => "#E7E0D3",
        "line" => "#D8D0C1",
        "field" => "#FFFFFF",
        "bar" => "#FFFFFF",
        "edge" => "#B9B2A5",
        "paper" => "#FFFFFF",
        "shadow" => "#1B1E2733",
        "primary" => "#1F5F5B",
        "primary_content" => "#FFFFFF",
        "secondary" => "#1F5F5B",
        "accent" => "#E8A33D",
        "accent_content" => "#1B1E27"
      }
    }
  ]

  def up do
    create table(:templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :description, :string
      # Code that draws the guest pages (KeepsakesWeb.Templates.renderers/0)
      add :renderer, :string, null: false, default: "trail"
      # Colours and fonts layered over the renderer's defaults
      add :theme, :map, null: false, default: %{}
      # Needs a plan with premium templates (enforced with billing)
      add :premium, :boolean, null: false, default: false
      add :active, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0
      # nil: a public template; set: a user's own private template (later)
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:templates, [:slug])
    create index(:templates, [:user_id])

    # nil falls back to the owner's default, then the system default
    alter table(:albums) do
      add :template_id, references(:templates, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:users) do
      add :default_template_id, references(:templates, type: :binary_id, on_delete: :nilify_all)
    end

    flush()

    now = DateTime.utc_now(:second)

    repo().insert_all(
      "templates",
      for t <- @templates do
        Map.merge(t, %{
          id: Ecto.UUID.bingenerate(),
          renderer: "trail",
          inserted_at: now,
          updated_at: now
        })
      end
    )

    execute "UPDATE albums SET template_id = (SELECT id FROM templates WHERE slug = 'trail')"
  end

  def down do
    alter table(:users), do: remove(:default_template_id)
    alter table(:albums), do: remove(:template_id)
    drop table(:templates)
  end
end
