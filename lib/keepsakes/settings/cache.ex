defmodule Keepsakes.Settings.Cache do
  @moduledoc """
  ETS read-through cache for `Keepsakes.Settings`, invalidated on every node
  via PubSub. Disabled in test (`config :keepsakes, #{inspect(__MODULE__)}, enabled: false`)
  so sandboxed tests never see each other's values.
  """
  use GenServer

  @table __MODULE__
  @topic "settings:invalidate"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def fetch(key) do
    if enabled?() do
      case :ets.lookup(@table, key) do
        [{^key, value}] -> {:ok, value}
        [] -> :miss
      end
    else
      :miss
    end
  end

  def put(key, value) do
    if enabled?(), do: :ets.insert(@table, {key, value})
    :ok
  end

  def invalidate(key) do
    if enabled?(), do: Phoenix.PubSub.broadcast(Keepsakes.PubSub, @topic, {:invalidate, key})
    :ok
  end

  defp enabled?, do: Application.get_env(:keepsakes, __MODULE__, [])[:enabled] != false

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    Phoenix.PubSub.subscribe(Keepsakes.PubSub, @topic)
    {:ok, nil}
  end

  @impl true
  def handle_info({:invalidate, key}, state) do
    :ets.delete(@table, key)
    {:noreply, state}
  end
end
