defmodule KeepsakesWeb.GuestAccess do
  @moduledoc """
  Who may see a shared album, for the guest pages under `/a`.

  A guest unlocks a link by entering its code (`KeepsakesWeb.GuestAccessController`),
  which records `link_id => code_version` in the session. Changing the code
  bumps the version, so old sessions stop matching; turning sharing off
  deletes the link. The album's owner always gets in, without a code.

  `on_mount` hooks:

    * `:link` - `/a/:slug`: assigns `@link`, `@album`, `@access`
      (`:owner | :guest | :none | :expired | :missing`), `@base_path` and
      the album's template (`KeepsakesWeb.Templates.assigns/1`)
    * `:preview` - `/a/preview/:album_slug`: the owner previews an album
      that may not be shared yet (requires login);
      `/a/preview/:album_slug/:template` previews it in another template
    * `:require_access` - redirects to the code page unless `:owner`/`:guest`
  """
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView

  alias Keepsakes.{Albums, Sharing, Templates}
  alias Keepsakes.Sharing.ShareLink

  @session_key "guest_links"
  # Keep the cookie small: remember the most recent links only
  @max_links 20

  ## Session (used by the controller)

  @doc "Remembers that this browser unlocked `link` at its current code version."
  def grant(conn, %ShareLink{id: id, code_version: version}) do
    links =
      conn
      |> Plug.Conn.get_session(@session_key)
      |> Kernel.||(%{})
      |> Map.delete(id)
      |> Enum.take(-(@max_links - 1))
      |> Map.new()
      |> Map.put(id, version)

    Plug.Conn.put_session(conn, @session_key, links)
  end

  @doc "Access level of the current visitor for `link`."
  def access(nil, _session, _scope), do: :missing

  def access(%ShareLink{} = link, session, scope) do
    cond do
      owner?(link, scope) -> :owner
      ShareLink.expired?(link, DateTime.utc_now()) -> :expired
      granted?(session, link) -> :guest
      true -> :none
    end
  end

  defp owner?(%ShareLink{user_id: user_id}, %{user: %{id: user_id}}), do: true
  defp owner?(_link, _scope), do: false

  defp granted?(session, %ShareLink{id: id, code_version: version}),
    do: get_in(session, [@session_key, id]) == version

  @doc "Path of the guest's first view for the link's default view."
  def start_path(base_path, %ShareLink{default_view: "slideshow"}), do: base_path <> "/slideshow"

  def start_path(base_path, %ShareLink{default_view: "autoscroll"}),
    do: base_path <> "/timeline?auto=1"

  def start_path(base_path, _link), do: base_path <> "/timeline"

  ## LiveView hooks

  def on_mount(:link, %{"slug" => slug}, session, socket) do
    link = Sharing.get_link_by_slug(slug)
    template = if link, do: Templates.for_album(link.album), else: Templates.system_default()

    {:cont,
     socket
     |> assign(
       link: link,
       album: link && link.album,
       owner_name: link && link.user.first_name,
       access: access(link, session, socket.assigns.current_scope),
       base_path: "/a/" <> slug,
       preview?: false,
       branding?: link == nil or Sharing.branding?(link.user_id)
     )
     |> assign(KeepsakesWeb.Templates.assigns(template))}
  end

  def on_mount(:preview, %{"album_slug" => album_slug} = params, _session, socket) do
    case socket.assigns.current_scope do
      %{user: %{} = user} = scope ->
        album = Albums.get_album_by_slug!(scope, album_slug)
        link = Sharing.get_link(scope, album) || %ShareLink{default_view: "timeline"}

        # /a/preview/:album_slug/:template tries a template before applying it
        {template, base_path} =
          case params do
            %{"template" => slug} ->
              {Templates.get_template(scope, slug), "/a/preview/#{album_slug}/#{slug}"}

            _ ->
              {Templates.for_album(album), "/a/preview/" <> album_slug}
          end

        if template do
          {:cont,
           socket
           |> assign(
             link: %{link | album: album, user: user},
             album: album,
             owner_name: user.first_name,
             access: :owner,
             base_path: base_path,
             preview?: true,
             branding?: Sharing.branding?(user.id)
           )
           |> assign(KeepsakesWeb.Templates.assigns(template))}
        else
          {:halt,
           socket
           |> put_flash(:error, "That template isn't available.")
           |> redirect(to: "/app/albums/#{album_slug}/template")}
        end

      _ ->
        {:halt,
         socket
         |> put_flash(:error, "You must log in to access this page.")
         |> redirect(to: "/auth/log-in")}
    end
  end

  def on_mount(:require_access, _params, _session, socket) do
    if socket.assigns.access in [:owner, :guest],
      do: {:cont, socket},
      else: {:halt, redirect(socket, to: socket.assigns.base_path)}
  end
end
