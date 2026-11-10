defmodule Keepsakes.Templates.Admin do
  @moduledoc """
  Public templates as staff manage them in the admin portal
  (`templates.manage`): a renderer (code) plus a theme (colours and fonts,
  `Keepsakes.Templates.Theme`). Templates are hidden (`active: false`)
  rather than deleted; albums on a hidden one fall back to their owner's
  or the system default, like `Keepsakes.Templates.for_album/1` already
  does. The system default can't be hidden. Changes are audited.
  """
  import Ecto.Query

  alias Keepsakes.Albums.Album
  alias Keepsakes.Templates.{Template, Theme}
  alias Keepsakes.{Audit, Repo, Staff, Templates}
  alias Keepsakes.Staff.Scope

  @doc "Public templates in gallery order, as `{template, albums using it}`."
  def list(%Scope{} = scope) do
    Staff.authorize!(scope, "templates.manage")

    counts =
      from(a in Album,
        where: not is_nil(a.template_id),
        group_by: a.template_id,
        select: {a.template_id, count(a.id)}
      )
      |> Repo.all()
      |> Map.new()

    from(t in Template, where: is_nil(t.user_id), order_by: [asc: t.position, asc: t.name])
    |> Repo.all()
    |> Enum.map(&{&1, Map.get(counts, &1.id, 0)})
  end

  def get!(%Scope{} = scope, id) do
    Staff.authorize!(scope, "templates.manage")
    Repo.one!(from t in Template, where: t.id == ^id and is_nil(t.user_id))
  end

  @doc "Templates that can be the default for new albums (visible and public)."
  def default_choices do
    Repo.all(
      from t in Template, where: t.active and is_nil(t.user_id), order_by: [t.position, t.name]
    )
  end

  @doc "Whether `template` is the one new albums get right now."
  def system_default?(%Template{id: id}), do: Templates.system_default().id == id

  def new_template, do: %Template{renderer: "trail", theme: %{}, active: false}

  @doc "A changeset for the form (theme fields left empty use the renderer's look)."
  def change(%Template{} = template, params \\ %{}),
    do: Template.changeset(template, attrs(template, params))

  def create(%Scope{} = scope, params) do
    Staff.authorize!(scope, "templates.manage")

    Repo.transact(fn ->
      with {:ok, template} <- new_template() |> change(params) |> Repo.insert() do
        Audit.record(scope, "template.created", {"template", template.id, template.name}, %{
          "theme" => template.theme
        })

        {:ok, template}
      end
    end)
  end

  def update(%Scope{} = scope, %Template{} = template, params) do
    Staff.authorize!(scope, "templates.manage")
    changeset = change(template, params)

    if Ecto.Changeset.get_field(changeset, :active) == false and system_default?(template) do
      {:error,
       Ecto.Changeset.add_error(
         %{changeset | action: :validate},
         :active,
         "is the default for new albums; choose another default in Settings first"
       )}
    else
      Repo.transact(fn ->
        with {:ok, updated} <- Repo.update(changeset) do
          changes =
            for f <- [:name, :description, :renderer, :theme, :premium, :active, :position],
                Map.get(template, f) != Map.get(updated, f),
                into: %{},
                do:
                  {to_string(f),
                   %{"before" => Map.get(template, f), "after" => Map.get(updated, f)}}

          if changes != %{},
            do:
              Audit.record(
                scope,
                "template.updated",
                {"template", template.id, updated.name},
                changes
              )

          {:ok, updated}
        end
      end)
    end
  end

  # The slug of an existing template never changes (albums and settings use it);
  # empty theme fields are dropped so the renderer's own colour applies
  defp attrs(template, params) do
    params = if template.id, do: Map.delete(params, "slug"), else: params

    case params["theme"] do
      %{} = theme ->
        Map.put(
          params,
          "theme",
          theme |> Enum.reject(fn {_k, v} -> v in [nil, ""] end) |> Map.new()
        )

      _ ->
        params
    end
  end

  @doc "Theme slots for the editor, with labels: `{colours, fonts}`."
  def theme_fields do
    colors =
      [
        {"page", "Page background"},
        {"ink", "Headings"},
        {"text", "Body text"},
        {"card", "Cards"},
        {"line", "Lines"},
        {"field", "Code boxes"},
        {"bar", "Progress bar"},
        {"edge", "Photo edges"},
        {"paper", "Polaroid paper"},
        {"shadow", "Shadows"},
        {"primary", "Buttons"},
        {"primary_content", "Button text"},
        {"secondary", "Secondary"},
        {"accent", "Accent"},
        {"accent_content", "Accent text"}
      ]
      |> Enum.filter(fn {slot, _} -> slot in Theme.color_slots() end)

    {colors, [{"display_font", "Headings font"}, {"hand_font", "Handwriting font"}]}
  end
end
