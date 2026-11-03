defmodule KeepsakesWeb.Templates.Trail do
  @moduledoc """
  The "Trail" renderer, the canvas design: polaroids zig-zag down a dashed
  trail on wide screens and alternate in one column on phones, with year
  markers where the year changes and "To be continued…" at the end; the
  slideshow is a tilted polaroid carousel over the same trail.

  Colours are the `ks-guest-*` tokens plus primary/secondary/accent, so
  templates such as "Daylight" restyle it with a theme alone.
  """
  @behaviour KeepsakesWeb.Templates.Renderer

  use KeepsakesWeb, :html

  import KeepsakesWeb.GuestComponents

  alias Keepsakes.Albums.Memory

  # Trail x positions: desktop canvas is 1000 wide, phone canvas 390 wide
  @desk %{left: 260, right: 740, center: 500}
  @phone %{left: 159, right: 231, center: 195}

  ## Access

  @impl true
  def unavailable(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:guest}>
      <main id="link-unavailable" class="flex min-h-screen items-center justify-center px-4 py-12">
        <div class="flex max-w-[460px] flex-col items-center gap-4 text-center">
          <.icon name="hero-link-slash" class="size-12 text-accent" />
          <h1 class="text-[32px] font-bold leading-tight">
            {if @access == :expired, do: "This link has expired", else: "This link isn't available"}
          </h1>
          <p class="text-[17px] text-ks-guest-text">
            The album may no longer be shared. Ask the person who sent it for a new link.
          </p>
        </div>
      </main>
    </Layouts.app>
    """
  end

  @impl true
  def access(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:guest}>
      <main class="flex min-h-screen items-center justify-center px-4 py-12">
        <div class="flex w-full max-w-[520px] flex-col items-center gap-7 text-center">
          <div class="relative h-[170px] w-[220px]" aria-hidden="true">
            <div class="absolute left-2.5 top-5 h-[140px] w-[130px] -rotate-9 rounded bg-ks-guest-card px-2 pb-6.5 pt-2">
              <div class="h-full bg-ks-guest-line"></div>
            </div>
            <div class="absolute right-2.5 top-2.5 h-[140px] w-[130px] rotate-7 rounded bg-ks-guest-card px-2 pb-6.5 pt-2">
              <div class="h-full bg-ks-guest-line"></div>
            </div>
            <div class="absolute left-[45px] top-0 flex h-[150px] w-[130px] -rotate-2 flex-col rounded bg-ks-guest-paper px-2 pb-7.5 pt-2 shadow-[0_16px_36px_var(--color-ks-guest-shadow)]">
              <div class="flex flex-1 items-center justify-center bg-ks-tint-sand">
                <.icon name="hero-lock-closed" class="size-7 text-ks-ink/50" />
              </div>
            </div>
          </div>

          <div class="flex flex-col gap-2.5">
            <span class="text-[15px] text-ks-guest-text">{@owner_name} shared an album with you</span>
            <h1 id="access-album-name" class="text-[44px] font-bold leading-[1.1]">{@album.name}</h1>
            <p class="text-[17px] text-ks-guest-text">Enter the 6-digit access code to open it.</p>
          </div>

          <.form
            for={%{}}
            id="access-form"
            action={@base_path <> "/access"}
            class="flex w-full flex-col items-center gap-5"
          >
            <fieldset
              id="access-digits"
              phx-hook=".CodeDigits"
              phx-update="ignore"
              class="flex justify-center gap-1.5 sm:gap-2"
            >
              <legend class="sr-only">Access code</legend>
              <input
                :for={i <- 1..6}
                id={"access-digit-#{i}"}
                name="code[]"
                type="text"
                inputmode="numeric"
                pattern="[0-9]"
                maxlength="1"
                autocomplete={if i == 1, do: "one-time-code", else: "off"}
                aria-label={"Digit #{i}"}
                required
                class="h-[66px] w-12 rounded-xl border border-ks-guest-edge bg-ks-guest-field text-center font-mono text-[28px] text-ks-guest-ink caret-accent transition-colors focus:border-2 focus:border-accent focus:outline-none sm:w-[54px]"
              />
            </fieldset>
            <button
              id="access-submit"
              type="submit"
              class="btn btn-primary h-[52px] w-full max-w-[380px] rounded-xl text-[17px] font-bold"
            >
              Open album
            </button>
          </.form>

          <p class="text-sm text-ks-guest-text">No code? Ask the person who sent you the link.</p>
        </div>
      </main>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CodeDigits">
        export default {
          mounted() {
            const boxes = [...this.el.querySelectorAll("input")]
            const submit = () => this.el.closest("form").requestSubmit()
            const fill = (start, text) => {
              const digits = text.replace(/\D/g, "").slice(0, boxes.length - start).split("")
              digits.forEach((d, i) => { boxes[start + i].value = d })
              const next = boxes.find(b => !b.value)
              ;(next || boxes[boxes.length - 1]).focus()
              if (!next) submit()
            }

            boxes.forEach((box, i) => {
              box.addEventListener("input", () => {
                const value = box.value.replace(/\D/g, "")
                box.value = ""
                if (value) fill(i, value)
              })
              box.addEventListener("keydown", e => {
                if (e.key === "Backspace" && !box.value && i > 0) {
                  boxes[i - 1].value = ""
                  boxes[i - 1].focus()
                  e.preventDefault()
                } else if (e.key === "ArrowLeft" && i > 0) {
                  boxes[i - 1].focus()
                } else if (e.key === "ArrowRight" && i < boxes.length - 1) {
                  boxes[i + 1].focus()
                }
              })
              box.addEventListener("paste", e => {
                e.preventDefault()
                fill(i, e.clipboardData.getData("text"))
              })
              box.addEventListener("focus", () => box.select())
            })
            boxes[0].focus()
          }
        }
      </script>
    </Layouts.app>
    """
  end

  ## Timeline

  @impl true
  def timeline(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:guest}>
      <.owner_banner
        album={@album}
        access={@access}
        preview?={@preview?}
        template={@template}
      />

      <div class="overflow-x-hidden px-4 pb-32">
        <header class="mx-auto flex max-w-[1000px] flex-col gap-10 pb-10 pt-6 md:gap-14 md:pb-16 md:pt-7">
          <div class="flex items-center justify-between gap-4">
            <.logo size={26} wordmark_class="text-lg" />
            <div class="flex flex-wrap justify-end gap-2.5">
              <.guest_nav_link
                :if={@uploads?}
                id="add-photos-link"
                navigate={@base_path <> "/add"}
                icon="hero-camera"
                label="Add photos"
              />
              <.guest_nav_link
                :if={@reactions?}
                id="guestbook-link"
                navigate={@base_path <> "/guestbook"}
                icon="hero-book-open"
                label="Guestbook"
              />
              <button
                id="autoscroll-toggle"
                type="button"
                phx-click={JS.dispatch("ks:autoscroll-toggle")}
                aria-pressed="false"
                aria-label="Auto-scroll"
                class="flex min-h-11 cursor-pointer items-center gap-2 rounded-full border border-ks-guest-edge px-3.5 font-medium text-ks-guest-ink transition-colors hover:border-ks-guest-ink md:px-4"
              >
                <.icon name="hero-arrow-down" class="size-4" />
                <span data-autoscroll-label class="hidden md:inline">Auto-scroll</span>
              </button>
              <.link
                id="play-slideshow"
                navigate={@base_path <> "/slideshow"}
                aria-label="Play as slideshow"
                class="flex min-h-11 items-center gap-2 rounded-full bg-primary px-3.5 font-bold text-primary-content no-underline transition hover:brightness-110 md:px-[18px]"
              >
                <.icon name="hero-play-solid" class="size-4" />
                <span class="hidden md:inline">Play as slideshow</span>
              </.link>
            </div>
          </div>

          <div class="flex flex-col items-center gap-2.5 text-center md:gap-3.5">
            <span
              id="timeline-summary"
              class="font-mono text-xs tracking-[0.12em] text-primary md:text-sm"
            >
              {summary(@memories)}
            </span>
            <h1 class="text-[44px] font-bold leading-none md:text-7xl">{@album.name}</h1>
            <p class="text-[15px] text-ks-guest-text md:text-lg">
              An album by {@owner_name}<span class="hidden md:inline"> · scroll to follow the trail</span>
            </p>
            <p :if={@album.description} class="max-w-xl text-[15px] text-ks-guest-text">
              {@album.description}
            </p>
          </div>
        </header>

        <%= if @memories == [] do %>
          <div
            id="timeline-empty"
            class="mx-auto flex max-w-md flex-col items-center gap-3 py-16 text-center"
          >
            <span class="font-hand text-4xl">Nothing here yet</span>
            <span class="text-ks-guest-text">Memories will appear here as they're added. Check back soon.</span>
          </div>
        <% else %>
          <div id="timeline" phx-update="stream" class="mx-auto flex max-w-[1000px] flex-col">
            <div :for={{dom_id, entry} <- @streams.entries} id={dom_id}>
              <.connector entry={entry} />
              <.memory_row
                entry={entry}
                show_details={@link.show_details}
                download_path={
                  @downloads? && !Memory.sealed?(entry.memory, @now) &&
                    "#{@base_path}/photos/#{entry.id}/download"
                }
                reactions?={@reactions? && @visitor_key != nil}
                now={@now}
              />
            </div>
          </div>

          <div class="mx-auto max-w-[1000px]">
            <.trail_end from={@last_side} branding?={@branding?} />
          </div>
        <% end %>
      </div>

      <div :if={!@preview?} class="flex justify-center pb-10">
        <.link
          id="report-album"
          navigate={@base_path <> "/report"}
          class="text-[13px] text-ks-guest-text no-underline hover:text-ks-guest-ink hover:underline"
        >
          Report this album
        </.link>
      </div>

      <.autoscroll_bar start={@auto?} />
      <script :type={Phoenix.LiveView.ColocatedHook} name=".AutoScroll">
        export default {
          mounted() {
            // Pixels per second, so the pace is the same at 60 Hz, 120 Hz or when frames drop
            this.pxPerSecond = {slow: 30, normal: 60, fast: 120}
            this.state = {on: false, paused: false, done: false, speed: "normal"}
            this.carry = 0
            this.toggle = document.getElementById("autoscroll-toggle")

            this.el.addEventListener("click", e => {
              const button = e.target.closest("[data-speed], [data-action]")
              if (!button) return
              const s = this.state
              if (button.dataset.speed) s.speed = button.dataset.speed
              else if (button.dataset.action === "stop") s.on = false
              else if (s.done) { window.scrollTo({top: 0}); s.done = false; s.paused = false }
              else s.paused = !s.paused
              this.render()
            })

            this.onToggle = () => this.set(!this.state.on)
            // Taking over by hand pauses rather than fighting the user
            this.onUser = () => {
              if (this.state.on && !this.state.paused && !this.state.done) { this.state.paused = true; this.render() }
            }
            window.addEventListener("ks:autoscroll-toggle", this.onToggle)
            window.addEventListener("wheel", this.onUser, {passive: true})
            window.addEventListener("touchstart", this.onUser, {passive: true})

            const tick = now => {
              const s = this.state
              // Cap each step so a hidden tab doesn't jump ahead when it comes back
              const seconds = Math.min((now - (this.last || now)) / 1000, 0.1)
              this.last = now
              if (s.on && !s.paused && !s.done) {
                this.carry += this.pxPerSecond[s.speed] * seconds
                const step = Math.floor(this.carry)
                if (step > 0) { this.carry -= step; window.scrollBy(0, step) }
                const page = document.scrollingElement
                if (page.scrollTop + window.innerHeight >= page.scrollHeight - 2) { s.done = true; this.render() }
              }
              this.frame = requestAnimationFrame(tick)
            }
            this.frame = requestAnimationFrame(tick)

            if (this.el.dataset.start === "true") this.set(true)
          },
          destroyed() {
            cancelAnimationFrame(this.frame)
            window.removeEventListener("ks:autoscroll-toggle", this.onToggle)
            window.removeEventListener("wheel", this.onUser)
            window.removeEventListener("touchstart", this.onUser)
          },
          set(on) {
            Object.assign(this.state, {on, paused: false, done: false})
            this.render()
          },
          render() {
            const {on, paused, done, speed} = this.state
            const running = on && !paused && !done
            this.el.hidden = !on
            this.el.dataset.running = running
            this.toggle.setAttribute("aria-pressed", on)
            const label = this.toggle.querySelector("[data-autoscroll-label]")
            if (label) label.textContent = on ? "Auto-scrolling" : "Auto-scroll"
            this.el.querySelector("[data-status]").textContent =
              done ? "Reached the end" : (paused ? "Paused" : "Auto-scrolling")
            this.el.querySelector("[data-action=pause]").setAttribute("aria-label",
              done ? "Replay from the top" : (paused ? "Resume" : "Pause"))
            this.el.querySelectorAll("[data-speed]").forEach(b => b.setAttribute("aria-pressed", b.dataset.speed === speed))
          }
        }
      </script>
    </Layouts.app>
    """
  end

  attr :entry, :map, required: true

  defp connector(%{entry: %{index: 0}} = assigns) do
    assigns = assign(assigns, desk: @desk, phone: @phone)

    ~H"""
    <div class="flex justify-center pb-2"><.year_chip year={@entry.memory.year} /></div>
    <.trail
      class="hidden md:block -mb-5"
      width={1000}
      height={70}
      d={"M#{@desk.center} 0 C#{@desk.center} 40 #{@desk[@entry.side]} 30 #{@desk[@entry.side]} 70"}
    />
    <.trail
      class="-mb-3.5 md:hidden"
      width={390}
      height={50}
      d={"M#{@phone.center} 0 C#{@phone.center} 30 #{@phone[@entry.side]} 20 #{@phone[@entry.side]} 50"}
    />
    """
  end

  defp connector(assigns) do
    %{entry: entry} = assigns
    {from, to} = {opposite(entry.side), entry.side}
    desk_h = if entry.year_chip, do: 190, else: 150
    phone_h = if entry.year_chip, do: 130, else: 100

    assigns =
      assign(assigns,
        desk_h: desk_h,
        phone_h: phone_h,
        desk_d:
          "M#{@desk[from]} 0 C#{@desk[from]} #{round(desk_h * 0.53)} #{@desk[to]} #{round(desk_h * 0.47)} #{@desk[to]} #{desk_h}",
        phone_d:
          "M#{@phone[from]} 0 C#{@phone[from]} #{round(phone_h * 0.55)} #{@phone[to]} #{round(phone_h * 0.45)} #{@phone[to]} #{phone_h}"
      )

    ~H"""
    <div class="relative -my-[30px] hidden md:block">
      <.trail width={1000} height={@desk_h} d={@desk_d} />
      <.year_chip
        :if={@entry.year_chip}
        year={@entry.year_chip}
        class="absolute left-1/2 top-1/2 -translate-1/2"
      />
    </div>
    <div class="relative -my-4 md:hidden">
      <.trail width={390} height={@phone_h} d={@phone_d} />
      <.year_chip
        :if={@entry.year_chip}
        year={@entry.year_chip}
        class="absolute left-1/2 top-1/2 -translate-1/2"
      />
    </div>
    """
  end

  attr :width, :integer, required: true
  attr :height, :integer, required: true
  attr :d, :string, required: true
  attr :class, :any, default: nil

  # The dashed trail, stretched to the column width
  defp trail(assigns) do
    ~H"""
    <svg
      viewBox={"0 0 #{@width} #{@height}"}
      preserveAspectRatio="none"
      aria-hidden="true"
      class={["block w-full", @class]}
      style={"height: #{@height}px"}
    >
      <path
        d={@d}
        fill="none"
        class="stroke-primary"
        stroke-width="2.5"
        stroke-dasharray="2 10"
        stroke-linecap="round"
        vector-effect="non-scaling-stroke"
      />
    </svg>
    """
  end

  attr :year, :integer, required: true
  attr :class, :any, default: nil

  defp year_chip(assigns) do
    ~H"""
    <span class={[
      "rounded-full border border-primary bg-ks-guest px-3.5 py-1 font-mono text-sm text-primary md:px-4 md:py-1.5 md:text-[15px]",
      @class
    ]}>
      {@year}
    </span>
    """
  end

  attr :entry, :map, required: true
  attr :show_details, :boolean, required: true
  attr :download_path, :any, default: false
  attr :reactions?, :boolean, default: false
  attr :now, :any, required: true

  # Time capsule: a sealed polaroid in the memory's place, with nothing of
  # the memory itself (Keepsakes.Sharing.guest_view/2 already stripped it)
  defp memory_row(assigns) do
    if Memory.sealed?(assigns.entry.memory, assigns.now),
      do: sealed_row(assigns),
      else: open_row(assigns)
  end

  defp sealed_row(assigns) do
    ~H"""
    <div class={[
      "relative z-[1] md:flex md:items-center md:gap-14 md:px-[8%]",
      @entry.side == :right && "md:justify-end"
    ]}>
      <article
        id={"sealed-#{@entry.id}"}
        class={[
          "relative w-[69%] rounded bg-ks-guest-paper p-2.5 pb-4 text-ks-ink shadow-[0_18px_36px_var(--color-ks-guest-shadow)] md:w-[39%] md:shrink-0 md:p-3.5 md:pb-5",
          if(@entry.side == :left, do: "ml-[6%] md:ml-0", else: "ml-[25%] md:ml-0"),
          tilt_class(@entry.index)
        ]}
      >
        <div class="flex aspect-[25/18] flex-col items-center justify-center gap-2 bg-ks-tint-sand">
          <.icon name="hero-lock-closed" class="size-9 text-ks-ink/50" />
          <span class="font-mono text-xs text-ks-stamp">Sealed</span>
        </div>
        <div class="flex flex-col gap-1 px-1 pt-2.5 md:px-1.5 md:pt-3">
          <h2 class="font-hand text-[26px] font-semibold leading-[1.1] md:text-[30px]">
            Opens on {Calendar.strftime(@entry.memory.reveal_at, "%-d %B %Y")}
          </h2>
        </div>
      </article>
    </div>
    """
  end

  defp open_row(assigns) do
    ~H"""
    <div class={[
      "relative z-[1] md:flex md:items-center md:gap-14 md:px-[8%]",
      @entry.side == :right && "md:justify-end"
    ]}>
      <article class={[
        "group relative w-[69%] rounded bg-ks-guest-paper p-2.5 pb-4 text-ks-ink shadow-[0_18px_36px_var(--color-ks-guest-shadow)] transition-transform duration-300 hover:rotate-0 hover:scale-[1.02] md:w-[39%] md:shrink-0 md:p-3.5 md:pb-5 md:shadow-[0_24px_50px_var(--color-ks-guest-shadow)]",
        if(@entry.side == :left, do: "ml-[6%] md:ml-0", else: "ml-[25%] md:ml-0"),
        tilt_class(@entry.index)
      ]}>
        <div class="relative aspect-[25/18] overflow-hidden bg-ks-tint-sand">
          <img
            src={photo_url(@entry.memory, 1200)}
            alt={@entry.memory.title}
            loading={if @entry.index < 2, do: "eager", else: "lazy"}
            decoding="async"
            class="size-full object-cover"
          />
          <span class="absolute bottom-2 right-2.5 hidden font-mono text-[13px] text-ks-stamp md:block">
            {stamp(@entry.memory)}
          </span>
          <a
            :if={@download_path}
            href={@download_path}
            aria-label={"Download #{@entry.memory.title}"}
            class="absolute right-2 top-2 flex size-9 items-center justify-center rounded-full bg-ks-guest-paper/85 text-ks-ink opacity-0 transition-opacity focus:opacity-100 group-hover:opacity-100"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" />
          </a>
        </div>
        <div class="flex flex-col gap-1 px-1 pt-2.5 md:px-1.5 md:pt-3">
          <span class="font-mono text-xs text-ks-stamp md:hidden">{card_line(
            @entry.memory,
            @show_details
          )}</span>
          <h2 class="font-hand text-[28px] font-semibold leading-[1.1] md:text-[34px]">
            {@entry.memory.title}
          </h2>
          <p
            :if={@show_details && @entry.memory.caption}
            class="text-sm leading-[1.45] text-ks-ink-soft md:text-[15px]"
          >
            {@entry.memory.caption}
          </p>
          <span :if={@entry.memory.source == "guest"} class="text-xs text-ks-stamp">
            Added by {@entry.memory.guest_name}
          </span>
          <.heart_button
            :if={@reactions?}
            id={"heart-#{@entry.id}"}
            memory_id={@entry.id}
            count={Map.get(@entry, :hearts, 0)}
            hearted?={Map.get(@entry, :hearted?, false)}
          />
        </div>
      </article>

      <div class={[
        "hidden flex-col gap-1.5 md:flex",
        @entry.side == :right && "md:order-first md:text-right"
      ]}>
        <span class="font-mono text-sm text-primary">
          {(@entry.index + 1) |> Integer.to_string() |> String.pad_leading(2, "0")}
        </span>
        <span class="text-3xl font-bold">{Memory.date_label(@entry.memory)}</span>
        <span :if={@show_details && place_line(@entry.memory)} class="text-base text-ks-guest-text">
          {place_line(@entry.memory)}
        </span>
      </div>
    </div>
    """
  end

  attr :from, :atom, required: true
  attr :branding?, :boolean, default: true

  defp trail_end(assigns) do
    assigns = assign(assigns, desk: @desk, phone: @phone)

    ~H"""
    <.trail
      class="-mt-[30px] hidden md:block"
      width={1000}
      height={120}
      d={"M#{@desk[@from]} 0 C#{@desk[@from]} 70 #{@desk.center} 60 #{@desk.center} 120"}
    />
    <.trail
      class="-mt-4 md:hidden"
      width={390}
      height={80}
      d={"M#{@phone[@from]} 0 C#{@phone[@from]} 45 #{@phone.center} 35 #{@phone.center} 80"}
    />
    <div id="timeline-end" class="flex flex-col items-center gap-2 text-center md:gap-2.5">
      <span class="size-3 rounded-full bg-primary md:size-3.5"></span>
      <span class="font-hand text-[34px] md:text-[40px]">To be continued…</span>
      <span :if={@branding?} class="text-sm text-ks-guest-text md:text-[15px]">
        Made with Keepsake
      </span>
    </div>
    """
  end

  attr :start, :boolean, default: false

  defp autoscroll_bar(assigns) do
    ~H"""
    <div
      id="autoscroll-bar"
      phx-hook=".AutoScroll"
      phx-update="ignore"
      data-start={to_string(@start)}
      data-running="false"
      aria-label="Auto-scroll controls"
      hidden
      class="group fixed bottom-6 left-1/2 z-20 flex -translate-x-1/2 items-center gap-2 whitespace-nowrap rounded-full border border-ks-guest-line bg-ks-guest-bar py-2 pl-[18px] pr-2 shadow-[0_16px_40px_var(--color-ks-guest-shadow)] [&[hidden]]:hidden"
    >
      <span
        aria-hidden="true"
        class="size-2 rounded-full bg-ks-guest-edge group-data-[running=true]:bg-secondary"
      ></span>
      <span data-status aria-live="polite" class="pr-1.5 text-sm font-medium">Auto-scrolling</span>
      <div class="flex gap-0.5 rounded-full bg-ks-guest p-[3px]">
        <button
          :for={{speed, label} <- [{"slow", "Slow"}, {"normal", "Normal"}, {"fast", "Fast"}]}
          type="button"
          data-speed={speed}
          aria-pressed={to_string(speed == "normal")}
          class="min-h-9 cursor-pointer rounded-full px-3 text-[13px] font-bold text-ks-guest-text transition-colors aria-pressed:bg-ks-guest-ink aria-pressed:text-ks-guest"
        >
          {label}
        </button>
      </div>
      <button
        type="button"
        data-action="pause"
        aria-label="Pause"
        class="flex size-11 cursor-pointer items-center justify-center rounded-full bg-primary text-primary-content"
      >
        <.icon name="hero-pause-solid" class="hidden size-[18px] group-data-[running=true]:block" />
        <.icon name="hero-play-solid" class="size-[18px] group-data-[running=true]:hidden" />
      </button>
      <button
        type="button"
        data-action="stop"
        aria-label="Stop auto-scroll"
        class="flex size-11 cursor-pointer items-center justify-center rounded-full border border-ks-guest-edge text-ks-guest-ink"
      >
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </div>
    """
  end

  defp opposite(:left), do: :right
  defp opposite(:right), do: :left

  ## Slideshow

  @impl true
  def slideshow(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:guest}>
      <.owner_banner
        album={@album}
        access={@access}
        preview?={@preview?}
        template={@template}
      />

      <div class="flex min-h-screen flex-col overflow-hidden">
        <header class="flex items-center justify-between gap-4 px-4 py-5 md:px-8">
          <div class="flex min-w-0 flex-col gap-0.5">
            <span class="truncate text-xl font-bold md:text-[22px]">{@album.name}</span>
            <span id="slideshow-counter" class="font-mono text-[13px] text-ks-guest-text">
              Memory 1 of {length(@memories)}
            </span>
          </div>
          <div class="flex shrink-0 gap-2.5">
            <div
              :if={@music_url}
              id="slideshow-music"
              phx-hook=".Music"
              phx-update="ignore"
              class="flex"
            >
              <audio data-audio src={@music_url} loop preload="none"></audio>
              <button
                type="button"
                data-music-toggle
                aria-pressed="false"
                class="flex min-h-11 cursor-pointer items-center gap-2 rounded-full border border-ks-guest-edge px-4 font-medium text-ks-guest-ink transition-colors hover:border-ks-guest-ink"
              >
                <.icon name="hero-musical-note" class="size-4" />
                <span data-music-label>Play with music</span>
              </button>
            </div>
            <.link
              id="exit-slideshow"
              navigate={@base_path <> "/timeline"}
              class="flex min-h-11 shrink-0 items-center gap-2 rounded-full border border-ks-guest-edge px-4 font-medium text-ks-guest-ink no-underline transition-colors hover:border-ks-guest-ink"
            >
              <.icon name="hero-x-mark" class="size-4" />
              <span class="hidden md:inline">Exit slideshow</span>
            </.link>
          </div>
        </header>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".Music">
          // Browsers only play sound after a tap, so music starts from the button
          export default {
            mounted() {
              const audio = this.el.querySelector("[data-audio]")
              const button = this.el.querySelector("[data-music-toggle]")
              const label = this.el.querySelector("[data-music-label]")
              const render = () => {
                const playing = !audio.paused
                button.setAttribute("aria-pressed", String(playing))
                label.textContent = playing ? "Mute music" : "Play with music"
              }
              button.addEventListener("click", () => {
                if (audio.paused) { audio.play().catch(() => {}) } else { audio.pause() }
              })
              audio.addEventListener("play", render)
              audio.addEventListener("pause", render)
            },
            destroyed() {
              const audio = this.el.querySelector("[data-audio]")
              if (audio) audio.pause()
            }
          }
        </script>

        <%= if @memories == [] do %>
          <div
            id="slideshow-empty"
            class="flex flex-1 flex-col items-center justify-center gap-3 px-4 text-center"
          >
            <span class="font-hand text-4xl">Nothing here yet</span>
            <span class="text-ks-guest-text">Memories will appear here as they're added.</span>
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
                class="pointer-events-none absolute left-1/2 top-1/2 w-[min(420px,78vw)] rounded bg-ks-guest-paper px-3.5 pb-6 pt-3.5 text-ks-ink opacity-0 shadow-[0_30px_60px_var(--color-ks-guest-shadow)] transition-[transform,opacity] duration-700 ease-[cubic-bezier(0.2,0.8,0.2,1)] motion-reduce:transition-none"
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
              <span data-caption-place class="min-h-[1.4em] text-[15px] text-ks-guest-text">
                {@link.show_details && place_line(hd(@memories))}
              </span>
            </div>

            <div class="mx-auto mt-7 flex w-full max-w-[760px] flex-col gap-5.5 px-6 pb-10">
              <div class="h-1 rounded-sm bg-ks-guest-card" aria-hidden="true">
                <div data-progress class="h-1 w-0 rounded-sm bg-primary"></div>
              </div>

              <div class="flex items-center justify-center gap-4">
                <button
                  type="button"
                  data-action="prev"
                  aria-label="Previous memory"
                  class="flex size-[52px] cursor-pointer items-center justify-center rounded-full border border-ks-guest-edge text-ks-guest-ink transition-colors hover:border-ks-guest-ink"
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
                  class="flex size-[52px] cursor-pointer items-center justify-center rounded-full border border-ks-guest-edge text-ks-guest-ink transition-colors hover:border-ks-guest-ink"
                >
                  <.icon name="hero-chevron-right" class="size-5" />
                </button>
                <button
                  type="button"
                  data-action="speed"
                  class="ml-2 min-h-11 cursor-pointer rounded-full border border-ks-guest-edge px-3.5 font-mono text-[13px] text-ks-guest-ink"
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
                    class="absolute left-5 right-5 top-[9px] border-t-2 border-dashed border-ks-guest-line"
                  ></span>
                  <button
                    :for={{memory, index} <- Enum.with_index(@memories)}
                    type="button"
                    data-stop={index}
                    aria-label={"#{memory.title}, #{Memory.date_label(memory)}"}
                    aria-current={if index == 0, do: "step", else: "false"}
                    class="group/stop relative flex min-w-11 shrink-0 cursor-pointer flex-col items-center gap-2"
                  >
                    <span class="size-5 rounded-full border-2 border-ks-guest-edge bg-ks-guest transition-colors group-aria-[current=step]/stop:border-primary group-aria-[current=step]/stop:bg-primary group-data-[seen=true]/stop:border-primary"></span>
                    <span class="font-mono text-xs text-ks-guest-text group-aria-[current=step]/stop:text-ks-guest-ink">
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

  ## Guest participation

  @impl true
  def add(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:guest}>
      <main class="mx-auto flex w-full max-w-[640px] flex-col gap-7 px-4 py-10">
        <.link
          id="add-back"
          navigate={@base_path <> "/timeline"}
          class="w-fit text-sm font-medium text-ks-guest-text no-underline hover:text-ks-guest-ink"
        >
          ← {@album.name}
        </.link>
        <div class="flex flex-col gap-2">
          <h1 class="text-[36px] font-bold leading-tight">Add your photos</h1>
          <p class="text-[17px] text-ks-guest-text">
            Share your photos of {@album.name} with {@owner_name}. They'll appear on the timeline once {@owner_name} approves them.
          </p>
        </div>

        <div
          :if={@added > 0}
          id="add-done"
          class="rounded-box border border-primary/40 bg-primary/10 px-5 py-4 text-[15px]"
        >
          {ngettext(
            "Thank you! Your photo was sent for approval.",
            "Thank you! Your %{count} photos were sent for approval.",
            @added
          )}
        </div>

        <.form
          for={@form}
          id="add-form"
          phx-change="validate"
          phx-submit="send"
          class="flex flex-col gap-5"
        >
          <label
            for={@uploads.photos.ref}
            phx-drop-target={@uploads.photos.ref}
            class="flex cursor-pointer flex-col items-center gap-2 rounded-2xl border-2 border-dashed border-ks-guest-edge px-6 py-10 text-center transition-colors hover:border-primary [&.phx-drop-target-active]:border-primary"
          >
            <.icon name="hero-camera" class="size-9 text-primary" />
            <span class="text-[17px] font-bold">Choose photos</span>
            <span class="text-sm text-ks-guest-text">
              Up to {@max_entries} at a time · JPG, PNG, HEIC or WebP · max {@max_upload_mb} MB each
            </span>
            <.live_file_input upload={@uploads.photos} class="sr-only" />
          </label>

          <ul :if={@uploads.photos.entries != []} id="add-queue" class="flex flex-col gap-2">
            <li
              :for={entry <- @uploads.photos.entries}
              id={"add-entry-#{entry.ref}"}
              class="flex items-center justify-between gap-3 rounded-field bg-ks-guest-card px-4 py-2.5 text-sm"
            >
              <span class="truncate">{entry.client_name}</span>
              <span :for={err <- upload_errors(@uploads.photos, entry)} class="text-error">
                {add_error_text(err)}
              </span>
              <button
                type="button"
                phx-click="cancel_entry"
                phx-value-ref={entry.ref}
                aria-label={"Remove #{entry.client_name}"}
                class="cursor-pointer text-ks-guest-text hover:text-ks-guest-ink"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </li>
          </ul>
          <p :for={err <- upload_errors(@uploads.photos)} class="text-sm text-error">
            {add_error_text(err)}
          </p>

          <.input field={@form[:guest_name]} label="Your name" maxlength="60" required />
          <div class="grid gap-4 sm:grid-cols-[minmax(0,1fr)_110px_110px]">
            <.input field={@form[:title]} label="What's happening? (optional)" maxlength="80" />
            <.input
              field={@form[:month]}
              type="select"
              label="Month"
              prompt="—"
              options={Enum.map(1..12, &{Calendar.strftime(Date.new!(2000, &1, 1), "%b"), &1})}
            />
            <.input
              field={@form[:year]}
              type="number"
              label="Year"
              min="1900"
              max={Date.utc_today().year}
            />
          </div>
          <.input field={@form[:caption]} type="textarea" label="A note (optional)" maxlength="280" />
          <p class="-mt-2 text-sm text-ks-guest-text">
            The details apply to every photo you send now.
          </p>
          <.input
            field={@form[:rights]}
            type="checkbox"
            label="I took these photos, or have permission to share them"
          />
          <p :if={@error} id="add-error" class="text-sm text-error">{@error}</p>
          <.button
            id="add-send"
            variant="primary"
            size="lg"
            phx-disable-with="Sending…"
            disabled={@uploads.photos.entries == []}
          >
            Send for approval
          </.button>
          <p class="text-center text-xs text-ks-guest-text">
            By sending photos you agree to the <.link
              href={~p"/terms"}
              target="_blank"
              class="underline"
            >Terms of use</.link>.
          </p>
        </.form>
      </main>
    </Layouts.app>
    """
  end

  defp add_error_text(:too_large), do: "Too large"
  defp add_error_text(:not_accepted), do: "Not a supported photo"
  defp add_error_text(:too_many_files), do: "Too many photos at once"
  defp add_error_text(_), do: "Couldn't add"

  @impl true
  def guestbook(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:guest}>
      <main class="mx-auto flex w-full max-w-[640px] flex-col gap-7 px-4 py-10">
        <.link
          id="guestbook-back"
          navigate={@base_path <> "/timeline"}
          class="w-fit text-sm font-medium text-ks-guest-text no-underline hover:text-ks-guest-ink"
        >
          ← {@album.name}
        </.link>
        <div class="flex flex-col gap-2">
          <h1 class="font-hand text-[52px] leading-none">Guestbook</h1>
          <p class="text-[17px] text-ks-guest-text">
            Leave a few words for {@owner_name}. Notes appear here once {@owner_name} approves them.
          </p>
        </div>

        <.form
          for={@form}
          id="guestbook-form"
          phx-change="validate"
          phx-submit="sign"
          class="flex flex-col gap-4 rounded-box bg-ks-guest-card p-5"
        >
          <.input field={@form[:name]} label="Your name" maxlength="60" required />
          <.input field={@form[:message]} type="textarea" label="Your note" maxlength="500" required />
          <.button id="guestbook-sign" variant="primary" phx-disable-with="Sending…">
            Sign the guestbook
          </.button>
        </.form>

        <div id="guestbook-notes" class="flex flex-col gap-4">
          <p :if={@notes == []} id="guestbook-empty" class="text-center text-ks-guest-text">
            No notes yet. Be the first.
          </p>
          <article
            :for={note <- @notes}
            id={"guestbook-note-#{note.id}"}
            class={[
              "flex flex-col gap-2 rounded bg-ks-guest-paper p-5 text-ks-ink shadow-[0_12px_28px_var(--color-ks-guest-shadow)]",
              tilt_class(:erlang.phash2(note.id, 6))
            ]}
          >
            <p class="whitespace-pre-line text-[15px] leading-relaxed">{note.message}</p>
            <div class="flex items-center justify-between gap-2">
              <span class="font-hand text-2xl">— {note.name}</span>
              <span
                :if={note.status == "pending"}
                class="rounded-full bg-ks-amber-soft px-2.5 py-0.5 text-xs font-bold text-ks-amber-deep"
              >
                Waiting for approval
              </span>
            </div>
          </article>
        </div>
      </main>
    </Layouts.app>
    """
  end

  @impl true
  def sealed(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:guest}>
      <main id="album-sealed" class="flex min-h-screen items-center justify-center px-4 py-12">
        <div class="flex w-full max-w-[520px] flex-col items-center gap-6 text-center">
          <div class="flex h-[150px] w-[130px] -rotate-2 flex-col rounded bg-ks-guest-paper px-2 pb-7.5 pt-2 shadow-[0_16px_36px_var(--color-ks-guest-shadow)]">
            <div class="flex flex-1 items-center justify-center bg-ks-tint-sand">
              <.icon name="hero-lock-closed" class="size-8 text-ks-ink/50" />
            </div>
          </div>
          <div class="flex flex-col gap-2">
            <span class="text-[15px] text-ks-guest-text">{@owner_name} made a time capsule</span>
            <h1 class="text-[40px] font-bold leading-[1.1]">{@album.name}</h1>
            <p class="text-[17px] text-ks-guest-text">
              Opens on
              <time datetime={DateTime.to_iso8601(@album.reveal_at)}>
                {Calendar.strftime(@album.reveal_at, "%-d %B %Y")}
              </time>
            </p>
          </div>
          <div
            id="sealed-countdown"
            phx-hook=".Countdown"
            phx-update="ignore"
            data-reveal={DateTime.to_iso8601(@album.reveal_at)}
            class="font-mono text-2xl tracking-[0.08em] text-primary"
          >
          </div>
        </div>
      </main>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Countdown">
        // Counts down in the guest's own time; reloads the page when it opens
        export default {
          mounted() {
            const reveal = new Date(this.el.dataset.reveal)
            const pad = (n) => String(n).padStart(2, "0")
            const tick = () => {
              const left = Math.max(0, reveal - new Date())
              if (left === 0) { clearInterval(this.timer); window.location.reload(); return }
              const s = Math.floor(left / 1000)
              const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600)
              const m = Math.floor(s % 3600 / 60)
              this.el.textContent = `${d}d ${pad(h)}h ${pad(m)}m ${pad(s % 60)}s`
            }
            tick()
            this.timer = setInterval(tick, 1000)
          },
          destroyed() { clearInterval(this.timer) }
        }
      </script>
    </Layouts.app>
    """
  end
end
