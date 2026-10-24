defmodule KeepsakesWeb.AuthThrottle do
  @moduledoc """
  Rate limits for the public auth endpoints, keyed by client IP and by the
  email being targeted, so neither one attacker nor one victim's inbox can be
  hammered.

  | Action                                  | Limit                               |
  |-----------------------------------------|-------------------------------------|
  | password log in                         | 20 / 15 min per IP, 8 / 15 min per email |
  | emailed links (sign-in, reset, confirm) | 10 / hour per IP, 3 / 15 min per email   |
  | registration                            | 10 / hour per IP                         |
  """
  alias Keepsakes.RateLimit

  @minute :timer.minutes(1)

  def login(ip, email) do
    with :ok <- RateLimit.check("auth:login:ip:#{ip}", 15 * @minute, 20) do
      RateLimit.check("auth:login:email:#{normalize(email)}", 15 * @minute, 8)
    end
  end

  def email_link(ip, email) do
    with :ok <- RateLimit.check("auth:link:ip:#{ip}", 60 * @minute, 10) do
      RateLimit.check("auth:link:email:#{normalize(email)}", 15 * @minute, 3)
    end
  end

  def register(ip) do
    RateLimit.check("auth:register:ip:#{ip}", 60 * @minute, 10)
  end

  @doc "A human message for a `{:rate_limited, retry_after_ms}` error."
  def message({:rate_limited, retry_after_ms}) do
    minutes = max(div(retry_after_ms, @minute) + 1, 1)

    "Too many attempts. Please try again in #{minutes} #{if minutes == 1, do: "minute", else: "minutes"}."
  end

  @doc "The client IP as a string, from a conn or LiveView peer data."
  def client_ip(%Plug.Conn{remote_ip: ip}), do: format_ip(ip)
  def client_ip(%{address: ip}), do: format_ip(ip)
  def client_ip(_), do: "unknown"

  defp format_ip(ip), do: ip |> :inet.ntoa() |> to_string()

  defp normalize(email) when is_binary(email), do: email |> String.trim() |> String.downcase()
  defp normalize(_), do: ""
end
