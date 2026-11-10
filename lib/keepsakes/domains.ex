defmodule Keepsakes.Domains do
  @moduledoc """
  Customers' own domains for their public site.

  A customer adds a hostname (`add/2`) and creates two DNS records: a TXT
  record `_keepsake.<hostname>` holding the domain's token (proof they own
  it) and a CNAME to our edge host (or, for a root domain, A records to our
  edge IPs). `check/1` looks both up; when they match the domain is
  `verified` and the site is served there (`site_for_host/1`).

  Pending domains are checked often for a day, then hourly up to a week,
  then given up on (`failed`); verified ones are re-checked daily and fail
  after three bad checks in a row (`check_due/1`, run by
  `Keepsakes.Domains.CheckWorker`). Customers are emailed either way.

  Adding a domain needs the `custom_domains` feature flag for the customer
  and room in their plan's `custom_domains` limit.
  """
  import Ecto.Query

  alias Keepsakes.Accounts.{Scope, User}
  alias Keepsakes.Albums.Album
  alias Keepsakes.Domains.{BlockedHostname, Domain, Notifier, Resolver}
  alias Keepsakes.Sharing.ShareLink
  alias Keepsakes.{Entitlements, Flags, Repo}

  @hostname ~r/\A(?=.{4,253}\z)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/

  ## Settings

  @doc "Where customers point their domains: `{edge_host, edge_ips}`."
  def edge,
    do:
      {Application.fetch_env!(:keepsakes, :edge_host),
       Application.get_env(:keepsakes, :edge_ips, [])}

  @doc "Whether the customer may use custom domains now (flag on and plan allows one)."
  def available?(%Scope{user: user} = scope),
    do: Flags.enabled?(:custom_domains, user) and limit(scope) != 0

  @doc "Whether the feature has been switched on for them (regardless of plan)."
  def flag_on?(%Scope{user: user}), do: Flags.enabled?(:custom_domains, user)

  defp limit(scope), do: Entitlements.limit(scope, :custom_domains)

  ## The owner's domains

  def list(%Scope{user: user}) do
    Repo.all(from d in Domain, where: d.user_id == ^user.id, order_by: d.inserted_at)
  end

  def get!(%Scope{user: user}, id), do: Repo.get_by!(Domain, id: id, user_id: user.id)

  @doc """
  Adds `hostname` for the customer. Returns `{:ok, domain}` or
  `{:error, reason}`: `:not_available` (flag/plan), `:limit_reached`,
  `:invalid`, `:ours`, `:blocked`, `:taken`.
  """
  def add(%Scope{user: user} = scope, hostname) do
    host = normalize(hostname)
    count = Repo.aggregate(from(d in Domain, where: d.user_id == ^user.id), :count)

    cond do
      not flag_on?(scope) or limit(scope) == 0 -> {:error, :not_available}
      limit(scope) != :unlimited and count >= limit(scope) -> {:error, :limit_reached}
      not Regex.match?(@hostname, host) -> {:error, :invalid}
      ours?(host) -> {:error, :ours}
      blocked?(host) -> {:error, :blocked}
      true -> insert(user, host)
    end
  end

  defp insert(user, host) do
    %Domain{
      user_id: user.id,
      hostname: host,
      verification_token:
        "keepsake-verify=" <>
          Base.encode32(:crypto.strong_rand_bytes(15), case: :lower, padding: false)
    }
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint(:hostname)
    |> Repo.insert()
    |> case do
      {:ok, domain} -> {:ok, domain}
      {:error, _} -> {:error, :taken}
    end
  end

  @doc "`\"https://Photos.Example.com/\"` -> `\"photos.example.com\"`."
  def normalize(hostname) do
    hostname
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r{\A[a-z]+://}, "")
    |> String.split(["/", "?", "#", ":"], parts: 2)
    |> hd()
    |> String.trim_trailing(".")
  end

  # Our own names and anything under them
  defp ours?(host) do
    main = KeepsakesWeb.Endpoint.host()
    {edge_host, _} = edge()

    Enum.any?([main, KeepsakesWeb.Hosts.admin_host(), edge_host], fn ours ->
      host == ours or String.ends_with?(host, "." <> ours)
    end) or String.ends_with?(host, ".localhost") or host == "localhost"
  end

  @doc "Whether staff have blocked this name."
  def blocked?(host), do: Enum.any?(Repo.all(BlockedHostname), &BlockedHostname.match?(&1, host))

  def remove(%Scope{} = scope, %Domain{} = domain) do
    domain = get!(scope, domain.id)
    Repo.delete(domain)
  end

  @doc "The DNS records the customer needs to create, for display."
  def records(%Domain{} = domain) do
    {edge_host, edge_ips} = edge()

    route =
      if Domain.apex?(domain) and edge_ips != [],
        do: Enum.map(edge_ips, &%{type: "A", name: domain.hostname, value: &1}),
        else: [%{type: "CNAME", name: domain.hostname, value: edge_host}]

    [%{type: "TXT", name: Domain.txt_name(domain), value: domain.verification_token} | route]
  end

  ## Checking DNS

  @doc """
  Looks up the domain's records and moves it along: pending → verified when
  both are right; verified → failed after three bad checks in a row; a
  failed domain that checks out is verified again. Blocked domains aren't
  touched. Returns the updated domain.
  """
  def check(domain, now \\ DateTime.utc_now(:second))

  def check(%Domain{status: "blocked"} = domain, _now), do: {:ok, domain}

  def check(%Domain{} = domain, now) do
    result = lookup(domain)

    {changes, notify} =
      case {domain.status, result} do
        {_, :ok} when domain.status != "verified" ->
          {[status: "verified", verified_at: now, checks: 0, last_error: nil], :verified}

        {"verified", :ok} ->
          {[checks: 0, last_error: nil], nil}

        {"verified", {:error, why}} when domain.checks + 1 >= 3 ->
          {[status: "failed", checks: 0, last_error: why], :failed}

        {_, {:error, why}} ->
          {[checks: domain.checks + 1, last_error: why], nil}
      end

    updated =
      domain
      |> Ecto.Changeset.change([last_checked_at: now] ++ changes)
      |> Repo.update!()

    notify(updated, notify)
    {:ok, updated}
  end

  defp lookup(domain) do
    resolver = Resolver.impl()
    {edge_host, edge_ips} = edge()

    txt_ok? = domain.verification_token in resolver.txt(Domain.txt_name(domain))

    routed? =
      edge_host in resolver.cname(domain.hostname) or
        (edge_ips != [] and Enum.any?(resolver.a(domain.hostname), &(&1 in edge_ips)))

    cond do
      not txt_ok? ->
        {:error, "the TXT record #{Domain.txt_name(domain)} with your code wasn't found"}

      not routed? ->
        {:error, "#{domain.hostname} doesn't point to #{edge_host} yet"}

      true ->
        :ok
    end
  end

  defp notify(_domain, nil), do: :ok

  defp notify(domain, kind) do
    user = Repo.get!(User, domain.user_id)

    case kind do
      :verified -> Notifier.deliver_verified(user, domain)
      :failed -> Notifier.deliver_failed(user, domain)
    end
  end

  @doc """
  Checks every domain that's due (see the module doc) and gives up on
  pending ones older than a week. Returns how many were checked.
  """
  def check_due(now \\ DateTime.utc_now(:second)) do
    from(d in Domain, where: d.status in ["pending", "verified"])
    |> Repo.all()
    |> Enum.filter(&due?(&1, now))
    |> Enum.map(fn domain ->
      if domain.status == "pending" and DateTime.diff(now, domain.inserted_at, :day) >= 7 do
        give_up(domain, now)
      else
        check(domain, now)
      end
    end)
    |> length()
  end

  @doc false
  def due?(%Domain{last_checked_at: nil}, _now), do: true

  def due?(%Domain{status: "pending"} = d, now) do
    every = if DateTime.diff(now, d.inserted_at, :hour) < 24, do: 600, else: 3600
    DateTime.diff(now, d.last_checked_at) >= every
  end

  def due?(%Domain{status: "verified"} = d, now),
    do: DateTime.diff(now, d.last_checked_at, :hour) >= 24

  def due?(_domain, _now), do: false

  defp give_up(domain, now) do
    updated =
      domain
      |> Ecto.Changeset.change(
        status: "failed",
        last_checked_at: now,
        last_error: domain.last_error || "the DNS records weren't found within a week"
      )
      |> Repo.update!()

    notify(updated, :failed)
    {:ok, updated}
  end

  ## Serving the site

  @doc """
  The verified domain for `host` with its owner, or nil (unknown, not
  verified, blocked, or the owner is suspended or deleting their account).
  """
  def site_for_host(host) when is_binary(host) do
    Repo.one(
      from d in Domain,
        join: u in assoc(d, :user),
        where:
          d.hostname == ^String.downcase(host) and d.status == "verified" and
            is_nil(u.suspended_at) and is_nil(u.deletion_requested_at),
        preload: [user: u]
    )
  end

  def site_for_host(_), do: nil

  @doc "Whether `host` belongs to any customer domain, whatever its status."
  def known_host?(host) when is_binary(host),
    do: Repo.exists?(from d in Domain, where: d.hostname == ^String.downcase(host))

  @doc "Albums on the owner's public site: chosen and shared, oldest first."
  def site_albums(%User{id: user_id}) do
    from(a in Album,
      join: l in ShareLink,
      on: l.album_id == a.id,
      where: a.user_id == ^user_id and a.show_on_site,
      order_by: [asc: a.inserted_at],
      preload: [:cover_memory]
    )
    |> Repo.all()
  end

  @doc "The share link of the owner's album with `album_slug`, as the guest pages need it."
  def site_link(%User{id: user_id}, album_slug) do
    Repo.one(
      from l in ShareLink,
        join: a in assoc(l, :album),
        join: u in assoc(l, :user),
        where: a.user_id == ^user_id and a.slug == ^album_slug,
        preload: [album: a, user: u]
    )
  end

  @doc "The owner's albums for the site settings, as `{album, shared?}`."
  def site_choices(%Scope{user: user}) do
    from(a in Album,
      left_join: l in ShareLink,
      on: l.album_id == a.id,
      where: a.user_id == ^user.id,
      order_by: [asc: a.inserted_at],
      select: {a, not is_nil(l.id)}
    )
    |> Repo.all()
  end

  @doc "Shows or hides an album on the owner's public site."
  def show_on_site(%Scope{user: user}, %Album{user_id: user_id} = album, show?)
      when user.id == user_id,
      do: album |> Ecto.Changeset.change(show_on_site: show?) |> Repo.update()
end
