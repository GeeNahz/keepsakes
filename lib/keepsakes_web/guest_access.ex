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
    * `:site` - a customer's own domain (`KeepsakesWeb.SiteRouter`):
      `@site`/`@site_owner`, plus the same as `:link` on `/:album` pages
      with `@base_path` = `/<album>`
    * `:preview` - `/a/preview/:album_slug`: the owner previews an album
      that may not be shared yet (requires login);
      `/a/preview/:album_slug/:template` previews it in another template
    * `:require_access` - redirects to the code page unless `:owner`/`:guest`
  """
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView

  alias Keepsakes.{Albums, Sharing, Templates}
  alias Keepsakes.Sharing.{Engagement, ShareLink}

  @session_key "guest_links"
  # A random id per guest browser: one heart per photo, rate limits, and
  # seeing your own pending guestbook note
  @visitor_key "guest_visitor"
  # Keep the cookie small: remember the most recent links only
  @max_links 20

  ## Session (used by the controller)

  @doc """
  Remembers that this browser unlocked `link` at its current code version,
  and gives the browser a random visitor key (hearts, guestbook, upload
  limits) if it has none yet.
  """
  def grant(conn, %ShareLink{id: id, code_version: version}) do
    links =
      conn
      |> Plug.Conn.get_session(@session_key)
      |> Kernel.||(%{})
      |> Map.delete(id)
      |> Enum.take(-(@max_links - 1))
      |> Map.new()
      |> Map.put(id, version)

    conn = Plug.Conn.put_session(conn, @session_key, links)

    if Plug.Conn.get_session(conn, @visitor_key),
      do: conn,
      else: Plug.Conn.put_session(conn, @visitor_key, new_visitor_key())
  end

  defp new_visitor_key, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

  # The owner (and collaborators previewing) count as one visitor each
  defp visitor_key(session, %{user: %{id: user_id}}, :owner),
    do: session[@visitor_key] || "user:" <> user_id

  defp visitor_key(session, _scope, _access), do: session[@visitor_key]

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
    {:cont, assign_link(socket, Sharing.get_link_by_slug(slug), session, "/a/" <> slug)}
  end

  # A customer's own domain (KeepsakesWeb.SiteRouter): the domain comes from
  # the LiveView session (`site_session/1`); albums are found by slug among
  # the owner's albums
  def on_mount(:site, params, session, socket) do
    case session["site_domain_id"] &&
           Keepsakes.Repo.get(Keepsakes.Domains.Domain, session["site_domain_id"]) do
      %{status: "verified"} = domain ->
        owner = Keepsakes.Repo.get!(Keepsakes.Accounts.User, domain.user_id)
        socket = assign(socket, site: domain, site_owner: owner)

        case params do
          %{"album" => album} ->
            {:cont,
             assign_link(socket, Keepsakes.Domains.site_link(owner, album), session, "/" <> album)}

          _ ->
            {:cont, socket}
        end

      _ ->
        {:halt, redirect(socket, to: "/")}
    end
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
             branding?: Sharing.branding?(user.id),
             visitor_key: nil,
             uploads?: false,
             reactions?: false,
             sealed?: false
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

  @doc "LiveView session for a customer's domain: which domain it is."
  def site_session(conn), do: %{"site_domain_id" => conn.assigns[:site] && conn.assigns.site.id}

  defp assign_link(socket, link, session, base_path) do
    template = if link, do: Templates.for_album(link.album), else: Templates.system_default()
    scope = socket.assigns.current_scope
    access = access(link, session, scope)

    socket
    |> assign(
      link: link,
      album: link && link.album,
      owner_name: link && link.user.first_name,
      access: access,
      base_path: base_path,
      preview?: false,
      branding?: link == nil or Sharing.branding?(link.user_id),
      visitor_key: visitor_key(session, scope, access)
    )
    |> assign(engagement_assigns(link, access))
    |> assign(KeepsakesWeb.Templates.assigns(template))
  end

  # What guests can do on this link, and whether the album is still sealed
  # (the owner always sees through the time capsule)
  defp engagement_assigns(%ShareLink{} = link, access) do
    [
      uploads?: Engagement.uploads_open?(link),
      reactions?: Engagement.reactions_open?(link),
      sealed?: access != :owner and Sharing.album_sealed?(link.album, DateTime.utc_now())
    ]
  end

  defp engagement_assigns(nil, _access), do: [uploads?: false, reactions?: false, sealed?: false]
end
