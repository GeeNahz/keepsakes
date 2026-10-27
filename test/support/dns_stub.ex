defmodule Keepsakes.DnsStub do
  @moduledoc """
  Fake DNS for tests (`config :keepsakes, :dns_resolver`). Records live in
  a public ETS table keyed by name, so they're visible from any process
  (LiveViews, workers); tests use unique hostnames, so they don't clash.

      DnsStub.put("_keepsake.photos.example.com", :txt, ["keepsake-verify=..."])
  """
  @behaviour Keepsakes.Domains.Resolver

  @table __MODULE__

  def start do
    if :ets.whereis(@table) == :undefined,
      do: :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

    :ok
  end

  def put(name, type, values), do: :ets.insert(@table, {{name, type}, values})

  def clear(name, type), do: :ets.delete(@table, {name, type})

  defp get(name, type) do
    case :ets.lookup(@table, {name, type}) do
      [{_, values}] -> values
      [] -> []
    end
  end

  @impl true
  def txt(name), do: get(name, :txt)
  @impl true
  def cname(name), do: get(name, :cname)
  @impl true
  def a(name), do: get(name, :a)
end
