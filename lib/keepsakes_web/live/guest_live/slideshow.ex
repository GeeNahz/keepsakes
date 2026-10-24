defmodule KeepsakesWeb.GuestLive.Slideshow do
  @moduledoc """
  `/a/:slug/slideshow`: memories as a tilted polaroid carousel over the
  trail, with play/pause, previous/next, 3/5/8 second pacing, a progress
  bar and jump-to stops.

  Every card is rendered once; the `.Slideshow` hook positions them,
  advances on a timer and updates the caption, so playback never waits on
  the server. Keys: ←/→ to move, space to play or pause. Swipe on phones.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.GuestComponents

  on_mount {KeepsakesWeb.GuestAccess, :require_access}

  alias Keepsakes.Albums.Memory
  alias Keepsakes.Sharing

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:guest}>
      <.owner_banner album={@album} access={@access} preview?={@preview?} />

      <div class="flex min-h-screen flex-col overflow-hidden">
        <header class="flex items-center justify-between gap-4 px-4 py-5 md:px-8">
          <div class="flex min-w-0 flex-col gap-0.5">
            <span class="truncate text-xl font-bold md:text-[22px]">{@album.name}</span>
            <span id="slideshow-counter" class="font-mono text-[13px] text-ks-night-text">
              Memory 1 of {length(@memories)}
            </span>
          </div>
          <.link
            id="exit-slideshow"
            navigate={@base_path <> "/timeline"}
            class="flex min-h-11 shrink-0 items-center gap-2 rounded-full border border-ks-muted px-4 font-medium text-white no-underline transition-colors hover:border-white"
          >
            <.icon name="hero-x-mark" class="size-4" /> Exit slideshow
          </.link>
        </header>

        <%= if @memories == [] do %>
          <div
            id="slideshow-empty"
            class="flex flex-1 flex-col items-center justify-center gap-3 px-4 text-center"
          >
            <span class="font-hand text-4xl">Nothing here yet</span>
            <span class="text-ks-night-text">Memories will appear here as they're added.</span>
          </div>
        <% else %>
          <div
            id="slideshow"
            phx-hook=".Slideshow"
            phx-update="ignore"
            data-count={length(@memories)}
            data-playing="true"
            tabindex="-1"
            class="group flex flex-1 flex-col outline-none"
          >
            <div data-stage class="relative h-[440px] shrink-0 touch-pan-y md:h-[560px]">
              <svg
                viewBox="0 0 1000 200"
                preserveAspectRatio="none"
                aria-hidden="true"
                class="absolute left-0 top-[34%] block h-[200px] w-full"
              >
                <path
                  d="M0 120 C 160 40, 300 180, 500 100 S 840 40, 1000 110"
                  fill="none"
                  class="stroke-primary"
                  stroke-width="2.5"
                  stroke-dasharray="2 10"
                  stroke-linecap="round"
                  vector-effect="non-scaling-stroke"
                />
              </svg>
              <article
                :for={{memory, index} <- Enum.with_index(@memories)}
                id={"slide-#{index}"}
                data-slide={index}
                data-tilt={tilt_degrees(index)}
                data-date={Memory.date_label(memory)}
                data-place={@link.show_details && place_line(memory)}
                aria-hidden={to_string(index != 0)}
                class="pointer-events-none absolute left-1/2 top-1/2 w-[min(420px,78vw)] rounded bg-white px-3.5 pb-6 pt-3.5 text-ks-ink opacity-0 shadow-[0_30px_60px_rgba(0,0,0,0.55)] transition-[transform,opacity] duration-700 ease-[cubic-bezier(0.2,0.8,0.2,1)] motion-reduce:transition-none"
              >
                <div class="relative aspect-[7/5] overflow-hidden bg-ks-tint-sand">
                  <img
                    src={photo_url(memory, 1200)}
                    alt={memory.title}
                    loading={if index < 3, do: "eager", else: "lazy"}
                    decoding="async"
                    class="size-full object-cover"
                  />
                  <span class="absolute bottom-2.5 right-3 font-mono text-sm text-ks-stamp">{stamp(
                    memory
                  )}</span>
                </div>
                <div class="flex flex-col gap-1.5 px-1.5 pt-3.5">
                  <h2 class="font-hand text-[34px] font-semibold leading-[1.05] md:text-[40px]">
                    {memory.title}
                  </h2>
                  <p
                    :if={@link.show_details && memory.caption}
                    class="text-[15px] leading-[1.45] text-ks-ink-soft md:text-base"
                  >
                    {memory.caption}
                  </p>
                </div>
              </article>
            </div>

            <div class="flex flex-col items-center gap-1.5 px-4 pt-1 text-center" aria-live="polite">
              <span data-caption-date class="text-[22px] font-bold md:text-[26px]">
                {Memory.date_label(hd(@memories))}
              </span>
              <span data-caption-place class="min-h-[1.4em] text-[15px] text-ks-night-text">
                {@link.show_details && place_line(hd(@memories))}
              </span>
            </div>

            <div class="mx-auto mt-7 flex w-full max-w-[760px] flex-col gap-5.5 px-6 pb-10">
              <div class="h-1 rounded-sm bg-ks-night-card" aria-hidden="true">
                <div data-progress class="h-1 w-0 rounded-sm bg-primary"></div>
              </div>

              <div class="flex items-center justify-center gap-4">
                <button
                  type="button"
                  data-action="prev"
                  aria-label="Previous memory"
                  class="flex size-[52px] cursor-pointer items-center justify-center rounded-full border border-ks-muted text-white transition-colors hover:border-white"
                >
                  <.icon name="hero-chevron-left" class="size-5" />
                </button>
                <button
                  type="button"
                  data-action="toggle"
                  aria-label="Pause slideshow"
                  class="flex size-[68px] cursor-pointer items-center justify-center rounded-full bg-primary text-primary-content transition hover:brightness-110"
                >
                  <.icon
                    name="hero-pause-solid"
                    class="hidden size-6 group-data-[playing=true]:block"
                  />
                  <.icon name="hero-play-solid" class="size-6 group-data-[playing=true]:hidden" />
                </button>
                <button
                  type="button"
                  data-action="next"
                  aria-label="Next memory"
                  class="flex size-[52px] cursor-pointer items-center justify-center rounded-full border border-ks-muted text-white transition-colors hover:border-white"
                >
                  <.icon name="hero-chevron-right" class="size-5" />
                </button>
                <button
                  type="button"
                  data-action="speed"
                  class="ml-2 min-h-11 cursor-pointer rounded-full border border-ks-muted px-3.5 font-mono text-[13px] text-white"
                >
                  Every <span data-speed>5</span> s
                </button>
              </div>

              <nav
                data-stops
                aria-label="Jump to a memory"
                class="relative overflow-x-auto pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
              >
                <div class="relative flex min-w-full justify-between gap-3">
                  <span
                    aria-hidden="true"
                    class="absolute left-5 right-5 top-[9px] border-t-2 border-dashed border-ks-night-line"
                  ></span>
                  <button
                    :for={{memory, index} <- Enum.with_index(@memories)}
                    type="button"
                    data-stop={index}
                    aria-label={"#{memory.title}, #{Memory.date_label(memory)}"}
                    aria-current={if index == 0, do: "step", else: "false"}
                    class="group/stop relative flex min-w-11 shrink-0 cursor-pointer flex-col items-center gap-2"
                  >
                    <span class="size-5 rounded-full border-2 border-ks-muted bg-ks-night transition-colors group-aria-[current=step]/stop:border-primary group-aria-[current=step]/stop:bg-primary group-data-[seen=true]/stop:border-primary"></span>
                    <span class="font-mono text-xs text-ks-night-text group-aria-[current=step]/stop:text-white">
                      {short_stop(memory)}
                    </span>
                  </button>
                </div>
              </nav>
            </div>
          </div>
        <% end %>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Slideshow">
        export default {
          mounted() {
            this.count = Number(this.el.dataset.count)
            this.slides = [...this.el.querySelectorAll("[data-slide]")]
            this.stops = [...this.el.querySelectorAll("[data-stop]")]
            this.state = {i: 0, playing: true, speed: 5, elapsed: 0}
            this.counter = document.getElementById("slideshow-counter")

            this.el.addEventListener("click", e => {
              const stop = e.target.closest("[data-stop]")
              if (stop) return this.go(Number(stop.dataset.stop))
              const action = e.target.closest("[data-action]")?.dataset.action
              if (action === "prev") this.go(this.state.i - 1)
              if (action === "next") this.go(this.state.i + 1)
              if (action === "toggle") this.togglePlay()
              if (action === "speed") this.cycleSpeed()
            })

            this.onKey = e => {
              if (e.target.closest("input, textarea, select")) return
              if (e.key === "ArrowLeft") this.go(this.state.i - 1)
              else if (e.key === "ArrowRight") this.go(this.state.i + 1)
              else if (e.key === " ") { e.preventDefault(); this.togglePlay() }
            }
            window.addEventListener("keydown", this.onKey)

            // Swipe left/right on the photos
            const stage = this.el.querySelector("[data-stage]")
            stage.addEventListener("touchstart", e => { this.touchX = e.touches[0].clientX }, {passive: true})
            stage.addEventListener("touchend", e => {
              const dx = e.changedTouches[0].clientX - this.touchX
              if (Math.abs(dx) > 40) this.go(this.state.i + (dx < 0 ? 1 : -1))
            })

            this.onResize = () => this.layout()
            window.addEventListener("resize", this.onResize)

            this.timer = setInterval(() => {
              if (!this.state.playing) return
              this.state.elapsed += 0.1
              if (this.state.elapsed >= this.state.speed) this.go(this.state.i + 1)
              else this.progress()
            }, 100)

            this.layout()
          },
          destroyed() {
            clearInterval(this.timer)
            window.removeEventListener("keydown", this.onKey)
            window.removeEventListener("resize", this.onResize)
          },
          go(i) {
            this.state.i = (i + this.count) % this.count
            this.state.elapsed = 0
            this.layout()
          },
          togglePlay() {
            this.state.playing = !this.state.playing
            this.el.dataset.playing = this.state.playing
            this.el.querySelector("[data-action=toggle]")
              .setAttribute("aria-label", this.state.playing ? "Pause slideshow" : "Play slideshow")
          },
          cycleSpeed() {
            const s = this.state
            s.speed = s.speed === 3 ? 5 : (s.speed === 5 ? 8 : 3)
            s.elapsed = 0
            this.el.querySelector("[data-speed]").textContent = s.speed
            this.progress()
          },
          progress() {
            const pct = Math.min(100, Math.round(this.state.elapsed / this.state.speed * 100))
            this.el.querySelector("[data-progress]").style.width = pct + "%"
          },
          layout() {
            const {i} = this.state
            // Neighbours sit closer on narrow screens so they still peek in
            const near = Math.min(520, window.innerWidth * 0.8)
            const far = Math.min(900, window.innerWidth * 1.3)
            this.slides.forEach((slide, j) => {
              const offset = j - i
              const a = Math.abs(offset)
              const sign = offset < 0 ? -1 : 1
              const tilt = Number(slide.dataset.tilt)
              const x = a === 0 ? 0 : (a === 1 ? near : far) * sign
              const rotate = a === 0 ? tilt : tilt + 4 * sign
              const scale = a === 0 ? 1 : (a === 1 ? 0.7 : 0.6)
              slide.style.transform = `translate(-50%, -50%) translateX(${x}px) rotate(${rotate}deg) scale(${scale})`
              slide.style.opacity = a === 0 ? 1 : (a === 1 ? 0.4 : 0)
              slide.style.zIndex = 3 - Math.min(a, 2)
              slide.setAttribute("aria-hidden", a !== 0)
            })
            const current = this.slides[i]
            this.el.querySelector("[data-caption-date]").textContent = current.dataset.date
            this.el.querySelector("[data-caption-place]").textContent = current.dataset.place || ""
            this.counter.textContent = `Memory ${i + 1} of ${this.count}`
            this.stops.forEach((stop, j) => {
              stop.setAttribute("aria-current", j === i ? "step" : "false")
              stop.dataset.seen = j < i
            })
            // Centre the current stop by scrolling only the strip (scrollIntoView
            // would also scroll the page sideways)
            const strip = this.el.querySelector("[data-stops]")
            const stop = this.stops[i]
            strip.scrollTo({left: stop.offsetLeft - (strip.clientWidth - stop.offsetWidth) / 2, behavior: "smooth"})
            this.progress()
          }
        }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    memories = Sharing.guest_memories(socket.assigns.album)

    {:ok,
     assign(socket, page_title: "Slideshow · #{socket.assigns.album.name}", memories: memories)}
  end
end
