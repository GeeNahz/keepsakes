defmodule KeepsakesWeb.GuestLive.Timeline do
  @moduledoc """
  `/a/:slug/timeline`: the guest memory timeline ("Trail"): polaroids
  zig-zag down a dashed trail on wide screens and alternate in one column
  on phones, with year markers where the year changes and "To be
  continued…" at the end.

  `?auto=1` starts auto-scroll (slow/normal/fast, pause, replay), run by
  the `.AutoScroll` hook; scrolling by hand pauses it.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.GuestComponents

  on_mount {KeepsakesWeb.GuestAccess, :require_access}

  alias Keepsakes.Albums.Memory
  alias Keepsakes.Sharing

  # Trail x positions: desktop canvas is 1000 wide, phone canvas 390 wide
  @desk %{left: 260, right: 740, center: 500}
  @phone %{left: 159, right: 231, center: 195}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:guest}>
      <.owner_banner album={@album} access={@access} preview?={@preview?} />

      <div class="overflow-x-hidden px-4 pb-32">
        <header class="mx-auto flex max-w-[1000px] flex-col gap-10 pb-10 pt-6 md:gap-14 md:pb-16 md:pt-7">
          <div class="flex items-center justify-between gap-4">
            <.logo size={26} wordmark_class="text-lg" />
            <div class="flex gap-2.5">
              <button
                id="autoscroll-toggle"
                type="button"
                phx-click={JS.dispatch("ks:autoscroll-toggle")}
                aria-pressed="false"
                aria-label="Auto-scroll"
                class="flex min-h-11 cursor-pointer items-center gap-2 rounded-full border border-ks-muted px-3.5 font-medium text-white transition-colors hover:border-white md:px-4"
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
            <p class="text-[15px] text-ks-night-text md:text-lg">
              An album by {@owner_name}<span class="hidden md:inline"> · scroll to follow the trail</span>
            </p>
            <p :if={@album.description} class="max-w-xl text-[15px] text-ks-night-text">
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
            <span class="text-ks-night-text">Memories will appear here as they're added. Check back soon.</span>
          </div>
        <% else %>
          <div id="timeline" phx-update="stream" class="mx-auto flex max-w-[1000px] flex-col">
            <div :for={{dom_id, entry} <- @streams.entries} id={dom_id}>
              <.connector entry={entry} />
              <.memory_row
                entry={entry}
                show_details={@link.show_details}
                download_path={@downloads? && "#{@base_path}/photos/#{entry.id}/download"}
              />
            </div>
          </div>

          <div class="mx-auto max-w-[1000px]">
            <.trail_end from={@last_side} />
          </div>
        <% end %>
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

  # The dashed amber trail, stretched to the column width
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
      "rounded-full border border-primary bg-ks-night px-3.5 py-1 font-mono text-sm text-primary md:px-4 md:py-1.5 md:text-[15px]",
      @class
    ]}>
      {@year}
    </span>
    """
  end

  attr :entry, :map, required: true
  attr :show_details, :boolean, required: true
  attr :download_path, :any, default: false

  defp memory_row(assigns) do
    ~H"""
    <div class={[
      "relative z-[1] md:flex md:items-center md:gap-14 md:px-[8%]",
      @entry.side == :right && "md:justify-end"
    ]}>
      <article class={[
        "group relative w-[69%] rounded bg-white p-2.5 pb-4 text-ks-ink shadow-[0_18px_36px_rgba(0,0,0,0.5)] transition-transform duration-300 hover:rotate-0 hover:scale-[1.02] md:w-[39%] md:shrink-0 md:p-3.5 md:pb-5 md:shadow-[0_24px_50px_rgba(0,0,0,0.5)]",
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
            class="absolute right-2 top-2 flex size-9 items-center justify-center rounded-full bg-white/85 text-ks-ink opacity-0 transition-opacity focus:opacity-100 group-hover:opacity-100"
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
        <span :if={@show_details && place_line(@entry.memory)} class="text-base text-ks-night-text">
          {place_line(@entry.memory)}
        </span>
      </div>
    </div>
    """
  end

  attr :from, :atom, required: true

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
      <span class="text-sm text-ks-night-text md:text-[15px]">Made with Keepsake</span>
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
      class="group fixed bottom-6 left-1/2 z-20 flex -translate-x-1/2 items-center gap-2 whitespace-nowrap rounded-full border border-ks-night-line bg-ks-night-bar py-2 pl-[18px] pr-2 shadow-[0_16px_40px_rgba(0,0,0,0.5)] [&[hidden]]:hidden"
    >
      <span
        aria-hidden="true"
        class="size-2 rounded-full bg-ks-field group-data-[running=true]:bg-secondary"
      ></span>
      <span data-status aria-live="polite" class="pr-1.5 text-sm font-medium">Auto-scrolling</span>
      <div class="flex gap-0.5 rounded-full bg-ks-night p-[3px]">
        <button
          :for={{speed, label} <- [{"slow", "Slow"}, {"normal", "Normal"}, {"fast", "Fast"}]}
          type="button"
          data-speed={speed}
          aria-pressed={to_string(speed == "normal")}
          class="min-h-9 cursor-pointer rounded-full px-3 text-[13px] font-bold text-ks-night-text transition-colors aria-pressed:bg-white aria-pressed:text-ks-night"
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
        class="flex size-11 cursor-pointer items-center justify-center rounded-full border border-ks-muted text-white"
      >
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </div>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    %{album: album, link: link, preview?: preview?} = socket.assigns
    memories = Sharing.guest_memories(album)
    entries = entries(memories)

    {:ok,
     socket
     |> assign(
       page_title: album.name,
       memories: memories,
       auto?: params["auto"] == "1",
       # The unshared preview has no public link to download through
       downloads?: link.allow_downloads == true and not preview?,
       last_side: entries |> List.last() |> then(&(&1 && &1.side)) || :left
     )
     |> stream(:entries, entries)}
  end

  # Each entry knows its side and whether a new year starts here
  defp entries(memories) do
    memories
    |> Enum.with_index()
    |> Enum.map(fn {memory, index} ->
      previous = if index > 0, do: Enum.at(memories, index - 1)

      %{
        id: memory.id,
        memory: memory,
        index: index,
        side: if(rem(index, 2) == 0, do: :left, else: :right),
        year_chip: previous && previous.year != memory.year && memory.year
      }
    end)
  end

  defp opposite(:left), do: :right
  defp opposite(:right), do: :left
end
