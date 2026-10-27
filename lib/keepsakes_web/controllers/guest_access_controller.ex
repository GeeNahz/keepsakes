defmodule KeepsakesWeb.GuestAccessController do
  @moduledoc """
  Guest actions that need a plain HTTP request:

    * `POST /a/:slug/access` - checks the 6-digit code (rate limited per
      link and IP), remembers the unlock in the session and opens the
      album's default view
    * `GET /a/:slug/photos/:id/download` - the full-size photo, when the
      owner allows downloads

  The same actions answer `/:album/...` on a customer's own domain.
  """
  use KeepsakesWeb, :controller

  alias Keepsakes.{RateLimit, Sharing, Storage}
  alias Keepsakes.Albums.Memory
  alias KeepsakesWeb.{AuthThrottle, GuestAccess}

  # 5 tries per 15 minutes for each link from one IP
  @window :timer.minutes(15)
  @tries 5

  def create(conn, params) do
    {link, base} = link_and_base(conn, params)

    with :ok <- check_available(link, conn),
         :ok <-
           RateLimit.check("share:#{link.id}:#{AuthThrottle.client_ip(conn)}", @window, @tries),
         true <- Sharing.code_matches?(link, typed_code(params)) do
      :ok = Sharing.record_open(link)

      conn
      |> GuestAccess.grant(link)
      |> redirect(to: GuestAccess.start_path(base, link))
    else
      {:error, {:rate_limited, retry_after_ms}} ->
        minutes = max(div(retry_after_ms, 60_000), 1)

        conn
        |> put_flash(:error, "Too many tries. Please wait #{minutes} min and try again.")
        |> redirect(to: base)

      {:error, :unavailable} ->
        redirect(conn, to: base)

      false ->
        conn
        |> put_flash(:error, "That code didn't work. Check it and try again.")
        |> redirect(to: base)
    end
  end

  def download(conn, %{"id" => id} = params) do
    {link, _base} = link_and_base(conn, params)
    access = GuestAccess.access(link, get_session(conn), conn.assigns[:current_scope])

    with true <- access == :owner or (access == :guest and Sharing.downloads_allowed?(link)),
         %Memory{} = memory <- Sharing.guest_memory(link.album, id),
         {:ok, data} <- Storage.get(Memory.variant_key(memory, 2400)) do
      send_download(conn, {:binary, data},
        filename: "#{Keepsakes.Albums.Album.slugify(memory.title)}.webp",
        content_type: "image/webp"
      )
    else
      _ -> send_resp(conn, :not_found, "Not found")
    end
  end

  # `/a/:slug` on the main site, or `/:album` on a customer's own domain
  # (KeepsakesWeb.SiteRouter puts the domain in conn.assigns.site)
  defp link_and_base(%{assigns: %{site: site}}, %{"album" => album}) do
    owner = Keepsakes.Repo.get!(Keepsakes.Accounts.User, site.user_id)
    {Keepsakes.Domains.site_link(owner, album), "/" <> album}
  end

  defp link_and_base(_conn, %{"slug" => slug}),
    do: {Sharing.get_link_by_slug(slug), "/a/" <> slug}

  defp check_available(nil, _conn), do: {:error, :unavailable}

  defp check_available(link, conn) do
    if GuestAccess.access(link, get_session(conn), nil) == :expired,
      do: {:error, :unavailable},
      else: :ok
  end

  # One field ("482917") or the six digit boxes (["4", "8", ...])
  defp typed_code(%{"code" => digits}) when is_list(digits), do: Enum.join(digits)
  defp typed_code(%{"code" => code}) when is_binary(code), do: code
  defp typed_code(_params), do: ""
end
