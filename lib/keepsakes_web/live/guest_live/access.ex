defmodule KeepsakesWeb.GuestLive.Access do
  @moduledoc """
  `/a/:slug`: the guest Access page. Six digit boxes post to
  `KeepsakesWeb.GuestAccessController` (rate limited there); guests who
  already unlocked the link, and the owner, go straight to the album.
  Unknown, turned-off and expired links get a gentle "not available" page.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Sharing
  alias KeepsakesWeb.GuestAccess

  @impl true
  def render(%{access: access} = assigns) when access in [:missing, :expired] do
    ~H"""
    <Layouts.app flash={@flash} shell={:guest}>
      <main id="link-unavailable" class="flex min-h-screen items-center justify-center px-4 py-12">
        <div class="flex max-w-[460px] flex-col items-center gap-4 text-center">
          <.icon name="hero-link-slash" class="size-12 text-ks-gold" />
          <h1 class="text-[32px] font-bold leading-tight">
            {if @access == :expired, do: "This link has expired", else: "This link isn't available"}
          </h1>
          <p class="text-[17px] text-ks-night-text">
            The album may no longer be shared. Ask the person who sent it for a new link.
          </p>
        </div>
      </main>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:guest}>
      <main class="flex min-h-screen items-center justify-center px-4 py-12">
        <div class="flex w-full max-w-[520px] flex-col items-center gap-7 text-center">
          <div class="relative h-[170px] w-[220px]" aria-hidden="true">
            <div class="absolute left-2.5 top-5 h-[140px] w-[130px] -rotate-9 rounded bg-ks-night-card px-2 pb-6.5 pt-2">
              <div class="h-full bg-ks-night-line"></div>
            </div>
            <div class="absolute right-2.5 top-2.5 h-[140px] w-[130px] rotate-7 rounded bg-ks-night-card px-2 pb-6.5 pt-2">
              <div class="h-full bg-ks-night-line"></div>
            </div>
            <div class="absolute left-[45px] top-0 flex h-[150px] w-[130px] -rotate-2 flex-col rounded bg-white px-2 pb-7.5 pt-2 shadow-[0_16px_36px_rgba(0,0,0,0.5)]">
              <div class="flex flex-1 items-center justify-center bg-ks-tint-sand">
                <.icon name="hero-lock-closed" class="size-7 text-ks-ink/50" />
              </div>
            </div>
          </div>

          <div class="flex flex-col gap-2.5">
            <span class="text-[15px] text-ks-night-text">{@owner_name} shared an album with you</span>
            <h1 id="access-album-name" class="text-[44px] font-bold leading-[1.1]">{@album.name}</h1>
            <p class="text-[17px] text-ks-night-text">Enter the 6-digit access code to open it.</p>
          </div>

          <.form
            for={%{}}
            id="access-form"
            action={~p"/a/#{@link.slug}/access"}
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
                class="h-[66px] w-12 rounded-xl border border-ks-muted bg-ks-night-field text-center font-mono text-[28px] text-white caret-accent transition-colors focus:border-2 focus:border-accent focus:outline-none sm:w-[54px]"
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

          <p class="text-sm text-ks-night-text">No code? Ask the person who sent you the link.</p>
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

  @impl true
  def mount(_params, _session, socket) do
    %{access: access, link: link, base_path: base} = socket.assigns

    case access do
      access when access in [:owner, :guest] ->
        # A returning guest counts as a visit; the owner peeking doesn't
        if access == :guest and not connected?(socket), do: Sharing.record_open(link)
        {:ok, push_navigate(socket, to: GuestAccess.start_path(base, link))}

      _ ->
        {:ok,
         assign(socket,
           page_title: (socket.assigns.album && socket.assigns.album.name) || "Keepsake"
         )}
    end
  end
end
