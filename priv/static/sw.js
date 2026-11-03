// Keepsake service worker: makes the app installable and keeps the shell
// fast on poor connections.
//
// - Static assets (digested CSS/JS, fonts, icons): cache first.
// - Pages are NEVER cached: albums sit behind access codes and sessions, so
//   HTML always comes from the server. Offline navigations get offline.html.
// - Photos aren't cached here: from object storage they're cross-origin
//   (opaque, and each would count ~7 MB against the storage quota), and
//   local /media URLs carry a new token each time. The browser's own HTTP
//   cache covers them, since signed URLs stay the same for 15 minutes
//   (Keepsakes.Storage.url/2).
const VERSION = "v1"
const STATIC = `keepsake-static-${VERSION}`
const OFFLINE = "/offline.html"

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(STATIC).then((cache) => cache.add(OFFLINE)).then(() => self.skipWaiting()))
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== STATIC).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  )
})

const isStatic = (url) =>
  url.origin === self.location.origin && /^\/(assets|fonts|images)\//.test(url.pathname)

self.addEventListener("fetch", (event) => {
  const { request } = event
  if (request.method !== "GET") return
  const url = new URL(request.url)

  if (request.mode === "navigate") {
    event.respondWith(fetch(request).catch(() => caches.match(OFFLINE)))
    return
  }

  if (isStatic(url)) {
    event.respondWith(
      caches.open(STATIC).then(async (cache) => {
        const hit = await cache.match(request)
        if (hit) return hit
        const response = await fetch(request)
        if (response.ok) cache.put(request, response.clone())
        return response
      })
    )
  }
})
