-- Step 4: may we have a certificate for this name? Asks the app
-- (GET /internal/tls/ask?domain=..., KeepsakesWeb.TlsAskController), which
-- says yes only for our own hosts and customers' verified, non-blocked
-- domains. Without this anyone could point a name at us and make us request
-- certificates for it, using up our Let's Encrypt rate limits.
--
-- Runs during the TLS handshake, so answers are kept for a minute in a
-- shared dict (one cache for all workers): a busy domain costs one call a
-- minute, and blocking a domain in the admin portal takes effect within it.
--
-- Step 6 adds a cap on how many *new* names may get certificates per minute
-- and per hour, on top of the app's yes.
local http = require("resty.http")
local backends = require("keepsake.backends")

local _M = {}

-- Asked of the app the name belongs to (keepsake/backends.lua): staging
-- approves its own hostnames, production everything else
local ASK_PATH = "/internal/tls/ask"
local TTL = 60
local cache = ngx.shared.tls_ask
local token = os.getenv("TLS_ASK_TOKEN")
-- A release answers in milliseconds, and a stuck app mustn't hold up
-- handshakes for long. The dev server checks your source for changes
-- before every request (seconds on a slow disk), so compose raises it.
local timeout_ms = tonumber(os.getenv("TLS_ASK_TIMEOUT_MS")) or 2000

-- Step 6: a cap on brand-new certificates. Let's Encrypt allows 300 new
-- orders per account per 3 hours; a burst of new names (many customers
-- verifying at once, or the certs volume lost) shouldn't use it all up.
-- Renewals don't count: they're exempt from that limit.
local NEW_PER_MINUTE = tonumber(os.getenv("ACME_NEW_PER_MINUTE")) or 10
local NEW_PER_HOUR = tonumber(os.getenv("ACME_NEW_PER_HOUR")) or 90

local function has_certificate(domain)
  local storage = require("resty.acme.autossl").storage
  return storage ~= nil and storage:get("domain:ecc:" .. domain) ~= nil
end

local function within_new_cap(domain)
  -- Each name counts once an hour, however often its order is retried or
  -- however many visitors arrive at once
  if not cache:add("new:" .. domain, true, 3600) then
    return true
  end

  local now = ngx.time()
  local minute = cache:incr("new_per_minute:" .. math.floor(now / 60), 1, 0, 120)
  local hour = cache:incr("new_per_hour:" .. math.floor(now / 3600), 1, 0, 7200)

  if (minute or 0) > NEW_PER_MINUTE or (hour or 0) > NEW_PER_HOUR then
    -- Not counted after all, so it's tried again on a later visit
    cache:delete("new:" .. domain)
    ngx.log(ngx.WARN, "new certificate for ", domain, " held back: over the cap of ",
      NEW_PER_MINUTE, "/min or ", NEW_PER_HOUR, "/hour")
    return false
  end

  return true
end

-- is_new_cert_needed is false when a certificate is about to be served and
-- true when one is about to be ordered (a new name or a renewal)
function _M.allowed(domain, is_new_cert_needed)
  domain = string.lower(domain)

  if not _M.approved(domain) then
    return false
  end

  if is_new_cert_needed and not has_certificate(domain) then
    return within_new_cap(domain)
  end

  return true
end

-- Whether the app says yes for this name (cached for a minute)
function _M.approved(domain)
  local cached = cache:get(domain)
  if cached ~= nil then
    return cached
  end

  local httpc = http.new()
  httpc:set_timeout(timeout_ms)

  local res, err = httpc:request_uri("http://" .. backends.for_host(domain) .. ASK_PATH, {
    query = { domain = domain },
    headers = { ["x-tls-ask-token"] = (token ~= "" and token) or nil },
  })

  -- The app is down or slow: say no for now, but don't remember it, so the
  -- next handshake asks again
  if not res then
    ngx.log(ngx.ERR, "tls ask for ", domain, " failed: ", err)
    return false
  end

  local allowed = res.status == 200
  if res.status ~= 200 and res.status ~= 404 then
    ngx.log(ngx.WARN, "tls ask for ", domain, " answered ", res.status)
  end

  cache:set(domain, allowed, TTL)
  return allowed
end

return _M
