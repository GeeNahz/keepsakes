defmodule Keepsakes.Entitlements do
  @moduledoc """
  What the user's current plan allows, checked inside the contexts (not
  just hidden in the UI).

  Values are read fresh from the subscription on every call rather than
  cached in the scope: a LiveView can stay open across a trial ending or
  a plan change, and the next check should follow the new plan.

  Limits are checked with `check/4` while the caller holds `lock/1`, so
  two uploads at the same moment can't both squeeze under a limit. Usage
  is counted live (storage is a sum over the user's photos), so there are
  no counters to drift.

  Going over a limit never deletes anything; it only stops additions
  (the account is "read-only" until it upgrades or makes room).
  """
  alias Keepsakes.Accounts.Scope
  alias Keepsakes.Billing
  alias Keepsakes.Billing.Features
  alias Keepsakes.{Format, Repo, Settings}

  @type over_limit :: {:over_limit, Features.key(), used :: integer(), limit :: integer()}

  @doc "The current plan's value for `key` (see `Keepsakes.Billing.Features.value/2`)."
  @spec get(Scope.t() | Ecto.UUID.t(), Features.key()) :: integer() | :unlimited | boolean()
  def get(scope_or_user_id, key), do: Features.value(features(scope_or_user_id), key)

  @doc "Every feature's current value, as `%{key => value}`."
  @spec all(Scope.t() | Ecto.UUID.t()) :: %{Features.key() => term()}
  def all(scope_or_user_id) do
    features = features(scope_or_user_id)
    Map.new(Features.keys(), &{&1, Features.value(features, &1)})
  end

  defp features(scope_or_user_id), do: Billing.current_plan(scope_or_user_id).features

  @doc "Whether a boolean feature is on."
  @spec can?(Scope.t() | Ecto.UUID.t(), Features.key()) :: boolean()
  def can?(scope_or_user_id, key), do: get(scope_or_user_id, key) == true

  @doc "A limit, as an integer or `:unlimited`."
  @spec limit(Scope.t() | Ecto.UUID.t(), Features.key()) :: integer() | :unlimited
  def limit(scope_or_user_id, key), do: get(scope_or_user_id, key)

  @doc """
  `:ok` when `used + adding` stays within the limit for `key`, else
  `{:error, {:over_limit, key, used, limit}}`.
  """
  @spec check(Scope.t(), Features.key(), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, over_limit()}
  def check(%Scope{} = scope, key, used, adding \\ 1) do
    case limit(scope, key) do
      :unlimited -> :ok
      max when used + adding <= max -> :ok
      max -> {:error, {:over_limit, key, used, max}}
    end
  end

  @doc """
  Largest single upload in MB: the plan's `max_upload_mb`, capped by the
  system-wide `Settings.max_upload_mb`.
  """
  @spec max_upload_mb(Scope.t()) :: pos_integer()
  def max_upload_mb(%Scope{} = scope) do
    ceiling = Settings.get(:max_upload_mb)

    case limit(scope, :max_upload_mb) do
      :unlimited -> ceiling
      mb -> min(mb, ceiling)
    end
  end

  @doc """
  Takes the user's limit lock until the surrounding transaction ends.
  Call it inside `Repo.transaction/1` before counting usage and writing.
  """
  @spec lock(Scope.t()) :: :ok
  def lock(%Scope{user: user}) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      "limits:" <> user.id
    ])

    :ok
  end

  @doc "Friendly text for an over-limit error, for flashes and notices."
  @spec message(over_limit()) :: String.t()
  def message({:over_limit, :storage_bytes, _used, max}),
    do: "You've used all #{Format.bytes(max)} of storage on your plan."

  def message({:over_limit, :max_albums, _used, max}),
    do: "Your plan includes #{max} #{if max == 1, do: "album", else: "albums"}."

  def message({:over_limit, :max_memories_per_album, _used, max}),
    do: "Albums on your plan hold up to #{max} photos."

  def message({:over_limit, :max_upload_mb, _used, max}),
    do: "Photos on your plan can be up to #{max} MB each."

  def message({:over_limit, _key, _used, _max}), do: "That's over your plan's limit."
end
