-- Which app a hostname belongs to. One edge can serve two environments on
-- one server (production and staging), so requests and certificate
-- questions must go to the right app. Set by three variables, the same
-- ones entrypoint.sh turns into nginx's `map $host $app_backend`:
--
--   APP_UPSTREAM      the default app, host:port (locally the dev server,
--                     app:4100; on the server app-production:4000)
--   STAGING_HOSTS     hostnames that belong to the other app, space-separated
--                     (staging.example.com admin.staging.example.com)
--   STAGING_UPSTREAM  that app's host:port (app-staging:4000)
--
-- nginx's map routes requests; this module answers the same question in
-- Lua, where nginx variables aren't available (during the TLS handshake).
-- With staging on its own server later, STAGING_HOSTS is simply left empty.
local _M = {}

local default = os.getenv("APP_UPSTREAM")
if default == nil or default == "" then
  default = "app:4100"
end

local staging = os.getenv("STAGING_UPSTREAM")
local staging_hosts = {}
for host in string.gmatch(os.getenv("STAGING_HOSTS") or "", "%S+") do
  staging_hosts[string.lower(host)] = true
end

-- host:port of the app serving `host`
function _M.for_host(host)
  if staging and staging ~= "" and staging_hosts[string.lower(host)] then
    return staging
  end
  return default
end

return _M
