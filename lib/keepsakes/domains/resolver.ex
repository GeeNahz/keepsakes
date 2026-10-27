defmodule Keepsakes.Domains.Resolver do
  @moduledoc """
  DNS lookups for domain checks, behind a behaviour so tests can stub
  them (`config :keepsakes, :dns_resolver, MyStub`). The default asks the
  system resolver through Erlang's `:inet_res`.
  """

  @doc "TXT strings for `name`."
  @callback txt(name :: String.t()) :: [String.t()]
  @doc "CNAME targets for `name` (lower-case, no trailing dot)."
  @callback cname(name :: String.t()) :: [String.t()]
  @doc "IPv4 addresses for `name`, as strings."
  @callback a(name :: String.t()) :: [String.t()]

  @behaviour __MODULE__

  def impl, do: Application.get_env(:keepsakes, :dns_resolver, __MODULE__)

  @impl true
  def txt(name) do
    name
    |> lookup(:txt)
    |> Enum.map(fn parts -> parts |> Enum.map(&to_string/1) |> Enum.join() end)
  end

  @impl true
  def cname(name), do: name |> lookup(:cname) |> Enum.map(&normalize/1)

  @impl true
  def a(name), do: name |> lookup(:a) |> Enum.map(&(&1 |> :inet.ntoa() |> to_string()))

  defp lookup(name, type) do
    :inet_res.lookup(String.to_charlist(name), :in, type, timeout: 5_000)
  end

  defp normalize(name), do: name |> to_string() |> String.downcase() |> String.trim_trailing(".")
end
