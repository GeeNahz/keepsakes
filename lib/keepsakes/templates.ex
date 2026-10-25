defmodule Keepsakes.Templates do
  @moduledoc """
  Guest templates: which look an album's guest pages use.

  Every album records its template. New albums get the owner's default
  template (account settings), else the system default
  (`Settings.default_template`). When an album's template is deactivated
  or deleted, the album falls back the same way, so guest pages always
  have a template to render.

  A template is available to a user when it's active and either public
  (`user_id` is nil) or their own. Premium templates are listed for
  everyone; plans gate them once billing lands.
  """
  import Ecto.Query

  alias Keepsakes.Accounts.{Scope, User}
  alias Keepsakes.Albums.Album
  alias Keepsakes.{Repo, Settings}
  alias Keepsakes.Templates.Template

  # Renderer names a template may use; the web layer maps each to a module
  @renderers ~w(trail)

  @doc "Renderer names a template may use."
  def renderers, do: @renderers

  @doc "Templates the user may pick, in gallery order."
  @spec list_templates(Scope.t()) :: [Template.t()]
  def list_templates(%Scope{} = scope) do
    scope |> available() |> order_by([t], asc: t.position, asc: t.name) |> Repo.all()
  end

  @doc "The available template with `slug`, or nil."
  @spec get_template(Scope.t(), String.t()) :: Template.t() | nil
  def get_template(%Scope{} = scope, slug) when is_binary(slug) do
    scope |> available() |> where([t], t.slug == ^slug) |> Repo.one()
  end

  defp available(%Scope{user: user}) do
    from t in Template,
      where: t.active and (is_nil(t.user_id) or t.user_id == ^user.id)
  end

  @doc """
  The system default: `Settings.default_template` when that template is
  active and public, else the first public template.
  """
  @spec system_default() :: Template.t()
  def system_default do
    slug = Settings.get(:default_template)

    from(t in Template,
      where: t.active and is_nil(t.user_id),
      order_by: [desc: t.slug == ^slug, asc: t.position],
      limit: 1
    )
    |> Repo.one!()
  end

  @doc "The template new albums get: the user's default, else the system default."
  @spec default_for(Scope.t()) :: Template.t()
  def default_for(%Scope{user: user} = scope) do
    (user.default_template_id &&
       scope |> available() |> where([t], t.id == ^user.default_template_id) |> Repo.one()) ||
      system_default()
  end

  @doc """
  The template an album's guest pages render with: its own, else its
  owner's default, else the system default.
  """
  @spec for_album(Album.t()) :: Template.t()
  def for_album(%Album{id: album_id}) do
    candidates =
      from(t in Template,
        join: a in Album,
        on: a.id == ^album_id,
        join: u in User,
        on: u.id == a.user_id,
        where: t.active and (is_nil(t.user_id) or t.user_id == a.user_id),
        where: t.id == a.template_id or t.id == u.default_template_id,
        order_by: [desc: t.id == a.template_id],
        limit: 1
      )

    Repo.one(candidates) || system_default()
  end

  @doc "Switches the album's guest pages to `template`."
  @spec set_album_template(Scope.t(), Album.t(), Template.t()) ::
          {:ok, Album.t()} | {:error, :unavailable}
  def set_album_template(
        %Scope{user: %{id: user_id}} = scope,
        %Album{user_id: user_id} = album,
        %Template{} = template
      ) do
    if available?(scope, template) do
      album |> Ecto.Changeset.change(template_id: template.id) |> Repo.update()
    else
      {:error, :unavailable}
    end
  end

  @doc "Sets the template new albums get. `nil` goes back to the system default."
  @spec set_default_template(Scope.t(), Template.t() | nil) ::
          {:ok, User.t()} | {:error, :unavailable}
  def set_default_template(%Scope{user: user} = scope, template) do
    cond do
      is_nil(template) -> update_default(user, nil)
      available?(scope, template) -> update_default(user, template.id)
      true -> {:error, :unavailable}
    end
  end

  defp update_default(user, template_id),
    do: user |> Ecto.Changeset.change(default_template_id: template_id) |> Repo.update()

  defp available?(%Scope{} = scope, %Template{id: id}),
    do: scope |> available() |> where([t], t.id == ^id) |> Repo.exists?()
end
