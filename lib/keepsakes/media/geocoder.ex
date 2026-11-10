defmodule Keepsakes.Media.Geocoder do
  @moduledoc """
  Turns photo GPS coordinates into a short place name ("Ikeja, Lagos")
  with OpenStreetMap Nominatim (free, no account).

  Nominatim's usage policy allows at most one request per second and asks
  for an identifying User-Agent; both are respected here. Coordinates are
  sent to Nominatim but never stored. Disable with `GEOCODER=none`.

  Config (`config :keepsakes, Keepsakes.Media.Geocoder`):

    * `:adapter` - `:nominatim` or `:none`
    * `:req_options` - merged into the request (tests plug in `Req.Test`)
  """
  require Logger

  @url "https://nominatim.openstreetmap.org/reverse"

  @doc "Place name for `{lat, lon}`, or `nil` when unknown or disabled."
  @spec reverse({float(), float()} | nil) :: String.t() | nil
  def reverse(nil), do: nil

  def reverse({lat, lon}) do
    case config()[:adapter] do
      :nominatim -> nominatim(lat, lon)
      _ -> nil
    end
  end

  defp nominatim(lat, lon) do
    with :ok <- wait_turn(),
         {:ok, %{status: 200, body: %{"address" => address}}} <-
           Req.get(@url, Keyword.merge(request_options(lat, lon), config()[:req_options] || [])) do
      place_name(address)
    else
      other ->
        Logger.info("Geocoding skipped: #{inspect(other, limit: 5)}")
        nil
    end
  end

  # One request per second across the node; wait briefly rather than skip
  defp wait_turn(attempts \\ 3)
  defp wait_turn(0), do: :rate_limited

  defp wait_turn(attempts) do
    case Keepsakes.RateLimit.hit("geocoder:nominatim", 1_000, 1) do
      {:allow, _} ->
        :ok

      {:deny, retry_after} ->
        Process.sleep(retry_after)
        wait_turn(attempts - 1)
    end
  end

  defp request_options(lat, lon) do
    {_name, from} = Application.fetch_env!(:keepsakes, :mail_from)

    [
      params: [
        format: "jsonv2",
        lat: Float.round(lat, 5),
        lon: Float.round(lon, 5),
        zoom: 14,
        "accept-language": "en"
      ],
      headers: [user_agent: "Keepsake/1.0 (#{from})"],
      receive_timeout: 5_000,
      retry: false
    ]
  end

  @doc false
  # "Neighbourhood, City" from a Nominatim address, most specific first.
  def place_name(address) do
    local = first(address, ~w(suburb neighbourhood quarter village town city_district hamlet))
    region = first(address, ~w(city town municipality county state))

    case Enum.uniq(Enum.reject([local, region], &is_nil/1)) do
      [] -> address["country"]
      parts -> Enum.join(parts, ", ")
    end
  end

  defp first(address, keys) do
    Enum.find_value(keys, fn key ->
      case address[key] do
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end
    end)
  end

  defp config, do: Application.get_env(:keepsakes, __MODULE__, adapter: :none)
end
