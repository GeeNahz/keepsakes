defmodule Keepsakes.Sharing do
  @moduledoc """
  Share links and guest access.

  Owner functions take the `%Scope{}`; guest functions work from the
  public slug and never expose the owner's other data. Guests only ever
  see complete memories: published, named, dated and processed.
  """
  import Ecto.Query

  alias Keepsakes.Accounts.Scope
  alias Keepsakes.Albums.{Album, Memory}
  alias Keepsakes.{Entitlements, Repo}
  alias Keepsakes.Sharing.{Notifier, ShareLink}

  @slug_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

  ## Owner side

  @doc "The album's share link, or `nil` when it isn't shared."
  @spec get_link(Scope.t(), Album.t()) :: ShareLink.t() | nil
  def get_link(%Scope{user: %{id: user_id}}, %Album{id: album_id, user_id: user_id}) do
    Repo.get_by(ShareLink, album_id: album_id)
  end

  @doc """
  Shares the album. `mode` is `"auto"` (random code) or `"manual"` with the
  owner's `code`.
  """
  @spec create_link(Scope.t(), Album.t(), String.t(), String.t() | nil) ::
          {:ok, ShareLink.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def create_link(scope, album, mode, code \\ nil)

  def create_link(
        %Scope{user: %{id: user_id} = user} = scope,
        %Album{user_id: user_id} = album,
        mode,
        code
      ) do
    with {:ok, code, origin} <- pick_code(mode, code) do
      # The owner's sharing defaults (settings) set up the new link
      %ShareLink{
        album_id: album.id,
        user_id: user_id,
        slug: new_slug(album),
        code: code,
        code_origin: origin,
        default_view: user.share_default_view || "timeline",
        show_details: user.share_show_details != false,
        allow_downloads:
          user.share_allow_downloads == true and Entitlements.can?(scope, :guest_downloads)
      }
      |> ShareLink.settings_changeset(%{expires_in: user.share_expires_in || "never"})
      |> Ecto.Changeset.unique_constraint(:album_id)
      |> Ecto.Changeset.unique_constraint(:slug)
      |> Repo.insert()
    end
  end

  @doc "Replaces the code (`\"auto\"` or `\"manual\"` + code) and locks out old guests."
  @spec change_code(Scope.t(), ShareLink.t(), String.t(), String.t() | nil) ::
          {:ok, ShareLink.t()} | {:error, String.t()}
  def change_code(scope, link, mode, code \\ nil)

  def change_code(%Scope{user: %{id: user_id}}, %ShareLink{user_id: user_id} = link, mode, code) do
    with {:ok, code, origin} <- pick_code(mode, code) do
      link
      |> Ecto.Changeset.change(
        code: code,
        code_origin: origin,
        code_version: link.code_version + 1
      )
      |> Repo.update()
    end
  end

  @spec change_settings(ShareLink.t(), map()) :: Ecto.Changeset.t()
  def change_settings(%ShareLink{} = link, attrs \\ %{}),
    do: ShareLink.settings_changeset(link, attrs)

  @doc "Saves expiry, default view, details and downloads."
  @spec update_settings(Scope.t(), ShareLink.t(), map()) ::
          {:ok, ShareLink.t()} | {:error, Ecto.Changeset.t()}
  def update_settings(
        %Scope{user: %{id: user_id}} = scope,
        %ShareLink{user_id: user_id} = link,
        attrs
      ) do
    changeset = ShareLink.settings_changeset(link, attrs)

    # Guest downloads are a plan feature; without it the switch stays off
    changeset =
      if Entitlements.can?(scope, :guest_downloads),
        do: changeset,
        else: Ecto.Changeset.put_change(changeset, :allow_downloads, false)

    Repo.update(changeset)
  end

  @doc """
  Whether guests may download photos: the owner turned it on and their
  plan still includes guest downloads.
  """
  @spec downloads_allowed?(ShareLink.t()) :: boolean()
  def downloads_allowed?(%ShareLink{allow_downloads: true, user_id: user_id}),
    do: Entitlements.can?(user_id, :guest_downloads)

  def downloads_allowed?(_link), do: false

  @doc "Whether the guest pages show \"Made with Keepsake\" for this owner."
  @spec branding?(Ecto.UUID.t()) :: boolean()
  def branding?(user_id), do: not Entitlements.can?(user_id, :remove_branding)

  @doc "Turns sharing off: the link and code stop working for everyone."
  @spec delete_link(Scope.t(), ShareLink.t()) :: {:ok, ShareLink.t()}
  def delete_link(%Scope{user: %{id: user_id}}, %ShareLink{user_id: user_id} = link),
    do: Repo.delete(link)

  @doc "Absolute URL guests open."
  def url(%ShareLink{slug: slug}), do: KeepsakesWeb.Endpoint.url() <> "/a/" <> slug

  @doc "The URL without the scheme, as shown to people (`keepsake.app/a/...`)."
  def display_url(link), do: link |> url() |> String.replace(~r{\Ahttps?://}, "")

  ## Guest side

  @doc "The link for a public slug with its album and owner, or `nil`."
  @spec get_link_by_slug(String.t()) :: ShareLink.t() | nil
  def get_link_by_slug(slug) when is_binary(slug) do
    # Links of an account paused for deletion or suspended don't open
    from(l in ShareLink,
      join: u in assoc(l, :user),
      where: l.slug == ^slug and is_nil(u.deletion_requested_at) and is_nil(u.suspended_at),
      preload: [:album, user: u]
    )
    |> Repo.one()
  end

  @doc "Constant-time check of a typed code against the link's code."
  @spec code_matches?(ShareLink.t(), String.t()) :: boolean()
  def code_matches?(%ShareLink{code: code}, typed) when is_binary(typed),
    do: Plug.Crypto.secure_compare(code, String.trim(typed))

  def code_matches?(_link, _typed), do: false

  @doc "Counts a guest visit for the owner's activity line."
  def record_open(%ShareLink{id: id}) do
    now = DateTime.utc_now(:second)

    from(l in ShareLink, where: l.id == ^id)
    |> Repo.update_all(inc: [open_count: 1, opens_since_digest: 1], set: [last_opened_at: now])

    :ok
  end

  @doc """
  Sends each owner with guest activity on (and visits since last time) one
  email listing which albums were opened and how often, then counts from
  zero again. Counts are cleared for owners with it off too, so turning it
  back on doesn't bring a pile-up. Returns how many emails were sent.
  """
  def send_guest_digests do
    links =
      from(l in ShareLink,
        join: u in assoc(l, :user),
        join: a in assoc(l, :album),
        where: l.opens_since_digest > 0 and is_nil(u.deletion_requested_at),
        preload: [user: u, album: a]
      )
      |> Repo.all()

    links
    |> Enum.group_by(& &1.user_id)
    |> Enum.count(fn {_user_id, [%{user: user} | _] = user_links} ->
      # Take away only what this email covers; visits arriving meanwhile stay
      Enum.each(user_links, fn link ->
        from(l in ShareLink, where: l.id == ^link.id)
        |> Repo.update_all(inc: [opens_since_digest: -link.opens_since_digest])
      end)

      if user.notify_guest_activity do
        visits = Enum.map(user_links, &{&1.album.name, &1.opens_since_digest})
        Notifier.deliver_guest_digest(user, visits)
        true
      else
        false
      end
    end)
  end

  @doc """
  What guests see: published memories with a name, date and processed
  photo, in timeline order.
  """
  @spec guest_memories(Album.t()) :: [Memory.t()]
  def guest_memories(%Album{id: album_id}) do
    from(m in Memory,
      where:
        m.album_id == ^album_id and m.status == "published" and m.processing == "ready" and
          not is_nil(m.title) and not is_nil(m.month) and not is_nil(m.year),
      order_by: [asc: m.year, asc: m.month, asc: m.position, asc: m.inserted_at]
    )
    |> Repo.all()
  end

  @doc "One of the guest's memories by id, or `nil` (used for downloads)."
  def guest_memory(%Album{} = album, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id) do
      album |> guest_memories() |> Enum.find(&(&1.id == uuid))
    else
      _ -> nil
    end
  end

  ## Codes and slugs

  defp pick_code("auto", _code), do: {:ok, random_code(), "auto"}

  defp pick_code("manual", code) do
    code = if is_binary(code), do: String.trim(code), else: code

    case ShareLink.validate_code(code) do
      :ok -> {:ok, code, "manual"}
      error -> error
    end
  end

  defp pick_code(_mode, _code), do: {:error, "Choose how to create the code."}

  @doc false
  def random_code do
    code =
      (100_000 + rem(:binary.decode_unsigned(:crypto.strong_rand_bytes(4)), 900_000))
      |> Integer.to_string()

    if ShareLink.validate_code(code) == :ok, do: code, else: random_code()
  end

  defp new_slug(%Album{slug: album_slug}) do
    suffix = for _ <- 1..4, into: "", do: <<Enum.random(@slug_alphabet)>>
    slug = "#{String.slice(album_slug, 0, 48)}-#{suffix}"

    if Repo.exists?(from l in ShareLink, where: l.slug == ^slug),
      do: new_slug(%Album{slug: album_slug}),
      else: slug
  end
end
