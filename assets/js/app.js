// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/keepsakes"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// JS.dispatch("ks:clear", to: "#input") empties an input after a submit,
// which a server re-render can't do while the input has focus
window.addEventListener("ks:clear", e => { e.target.value = "" })

// JS.dispatch("ks:print") opens the browser's print dialog (receipts)
window.addEventListener("ks:print", () => window.print())

// JS.dispatch("ks:reveal") on an item in a horizontally scrolling row
// centres it by scrolling only the row (scrollIntoView can shift the page)
window.addEventListener("ks:reveal", e => {
  const row = e.target.parentElement
  if (row.scrollWidth <= row.clientWidth) return
  row.scrollLeft = e.target.offsetLeft - row.offsetLeft - (row.clientWidth - e.target.offsetWidth) / 2
})

// JS.dispatch("ks:copy", detail: %{from: "#selector"}) on a button copies the
// target's value (or text) and briefly swaps the button's
// [data-copy-label] text to "Copied"
// Older/insecure contexts (plain http off localhost) have no Clipboard API:
// copy through a selected, off-screen textarea instead
const legacyCopy = text => {
  const area = Object.assign(document.createElement("textarea"), {value: text, readOnly: true})
  area.style.cssText = "position:fixed;left:-9999px;opacity:0"
  document.body.appendChild(area)
  area.select()
  const ok = document.execCommand("copy")
  area.remove()
  return ok ? Promise.resolve() : Promise.reject(new Error("copy failed"))
}

window.addEventListener("ks:copy", e => {
  const source = document.querySelector(e.detail.from)
  if (!source) return
  const text = ("value" in source ? source.value : source.textContent).trim()
  const copy = navigator.clipboard ? navigator.clipboard.writeText(text).catch(() => legacyCopy(text)) : legacyCopy(text)
  const label = e.target.querySelector("[data-copy-label]") || e.target
  label.dataset.original ||= label.textContent

  copy
    .then(() => { label.textContent = "Copied" })
    .catch(() => { label.textContent = "Press Ctrl+C"; if (source.select) source.select() })
    .finally(() => {
      clearTimeout(label.copyTimer)
      label.copyTimer = setTimeout(() => { label.textContent = label.dataset.original }, 2000)
    })
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

