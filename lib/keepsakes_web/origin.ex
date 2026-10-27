defmodule KeepsakesWeb.Origin do
  @moduledoc """
  Which pages may open LiveView sockets (the endpoint's `check_origin`):
  the main site, the admin portal and customers' verified domains.
  """

  @doc "Whether a socket from `uri` is allowed."
  def allowed?(%URI{host: host}) when is_binary(host) do
    host in [KeepsakesWeb.Endpoint.host(), KeepsakesWeb.Hosts.admin_host()] or
      Keepsakes.Domains.site_for_host(host) != nil
  end

  def allowed?(_uri), do: false
end
