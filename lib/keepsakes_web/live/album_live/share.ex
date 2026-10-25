defmodule KeepsakesWeb.AlbumLive.Share do
  @moduledoc """
  `/albums/:slug/share`: the Share page from the canvas.

  Not shared yet: pick how the access code is made (random or your own)
  and create the link. Shared: copy the link, the code and an invite
  message, change the code (which locks out old guests), adjust guest
  settings, see activity, or turn sharing off.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.{Albums, Entitlements, Sharing}
  alias Keepsakes.Sharing.ShareLink
  alias KeepsakesWeb.OwnerShell

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} owner={@owner} sidebar={false}>
      <div class="mx-auto flex w-full max-w-[1040px] flex-col gap-6">
        <div class="flex flex-col gap-1.5">
          <.link
            id="share-back"
            navigate={~p"/albums/#{@album.slug}"}
            class="w-fit text-sm font-medium no-underline"
          >
            ← {@album.name}
          </.link>
          <h1 class="text-[32px] font-bold">Share this album</h1>
          <p class="text-base text-ks-muted">
            Send the link and the access code. Anyone with both can open the timeline, no account needed.
          </p>
        </div>

        <div class="grid items-start gap-6 [grid-template-columns:repeat(auto-fit,minmax(320px,1fr))]">
          <%= if @link do %>
            <.live_link_card link={@link} album={@album} editing={@editing} code_error={@code_error} />
          <% else %>
            <.setup_card mode={@mode} code_error={@code_error} />
          <% end %>

          <.settings_card link={@link} form={@settings_form} downloads?={@downloads?} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :mode, :string, required: true
  attr :code_error, :string, default: nil

  defp setup_card(assigns) do
    ~H"""
    <section
      id="share-setup"
      aria-label="Set up sharing"
      class="flex flex-col gap-5.5 rounded-2xl border border-base-300 bg-base-100 p-7"
    >
      <div class="flex items-center gap-4">
        <div class="flex size-14 shrink-0 items-center justify-center rounded-[14px] bg-ks-amber-soft">
          <.icon name="hero-lock-closed" class="size-[26px] text-ks-amber-deep" />
        </div>
        <div class="flex flex-col gap-1">
          <span class="text-lg font-bold">Not shared yet</span>
          <span class="text-sm text-ks-muted">
            Only you can see this album. Create a link to invite others.
          </span>
        </div>
      </div>

      <form
        id="share-create-form"
        phx-change="pick_mode"
        phx-submit="create"
        class="flex flex-col gap-5.5"
      >
        <fieldset class="flex flex-col gap-2.5">
          <legend class="pb-2.5 text-sm font-bold">How should the access code be created?</legend>
          <.mode_option
            value="auto"
            mode={@mode}
            title="Generate automatically"
            text="We create a random 6-digit code. You can replace it any time."
          />
          <.mode_option
            value="manual"
            mode={@mode}
            title="Set my own code"
            text="Choose 6 digits your family will remember."
          />
        </fieldset>

        <div :if={@mode == "manual"} class="flex flex-col gap-1.5">
          <label for="share-own-code" class="text-sm font-bold">Your access code</label>
          <.code_input id="share-own-code" class="w-[220px] text-[22px]" />
          <.code_hint error={@code_error} />
        </div>

        <.button id="share-create" variant="primary" size="lg" phx-disable-with="Creating…">
          Create share link
        </.button>
      </form>
    </section>
    """
  end

  attr :value, :string, required: true
  attr :mode, :string, required: true
  attr :title, :string, required: true
  attr :text, :string, required: true

  defp mode_option(assigns) do
    ~H"""
    <label
      id={"share-mode-#{@value}"}
      class={[
        "flex cursor-pointer items-start gap-3 rounded-xl border-2 px-4 py-3.5 transition-colors",
        if(@mode == @value,
          do: "border-primary bg-ks-teal-tint",
          else: "border-base-300 hover:border-ks-field"
        )
      ]}
    >
      <input
        type="radio"
        name="mode"
        value={@value}
        checked={@mode == @value}
        class="radio radio-primary radio-sm mt-0.5"
      />
      <span class="flex flex-col gap-0.5">
        <span class="font-bold">{@title}</span>
        <span class="text-sm text-ks-muted">{@text}</span>
      </span>
    </label>
    """
  end

  attr :id, :string, required: true
  attr :class, :any, default: nil

  defp code_input(assigns) do
    ~H"""
    <input
      id={@id}
      type="text"
      name="code"
      inputmode="numeric"
      pattern="[0-9]*"
      maxlength="6"
      autocomplete="off"
      placeholder="6 digits"
      class={[
        "input h-12 border-ks-field bg-base-100 px-3.5 font-mono tracking-[0.3em]",
        @class
      ]}
    />
    """
  end

  attr :error, :string, default: nil

  defp code_hint(assigns) do
    ~H"""
    <span
      id="share-code-hint"
      class={["text-[13px]", if(@error, do: "text-error", else: "text-ks-muted")]}
    >
      {@error || "Numbers only, 6 digits. Avoid birthdays others could guess."}
    </span>
    """
  end

  attr :link, ShareLink, required: true
  attr :album, :map, required: true
  attr :editing, :boolean, required: true
  attr :code_error, :string, default: nil

  defp live_link_card(assigns) do
    assigns =
      assign(assigns,
        display_url: Sharing.display_url(assigns.link),
        invite:
          "I made an album, “#{assigns.album.name}”. Open #{Sharing.display_url(assigns.link)} and use the code #{assigns.link.code}."
      )

    ~H"""
    <section
      id="share-live"
      aria-label="Link and code"
      class="flex flex-col gap-6 rounded-2xl border border-base-300 bg-base-100 p-7"
    >
      <div class="flex flex-col gap-2">
        <label for="share-link-url" class="text-sm font-bold">Album link</label>
        <div class="flex gap-2">
          <input
            id="share-link-url"
            type="text"
            readonly
            value={@display_url}
            class="input h-12 min-w-0 flex-1 border-ks-field bg-base-200 px-3.5 font-mono text-sm"
          />
          <.button
            id="copy-link"
            type="button"
            variant="secondary"
            phx-click={JS.dispatch("ks:copy", detail: %{from: "#share-link-url"})}
          >
            <span data-copy-label>Copy link</span>
          </.button>
        </div>
      </div>

      <div class="flex flex-col gap-2.5">
        <div class="flex items-center gap-2.5">
          <span class="text-sm font-bold">Access code</span>
          <.badge variant="muted">
            {if @link.code_origin == "auto", do: "Generated automatically", else: "Set by you"}
          </.badge>
        </div>
        <div class="flex flex-wrap items-center gap-3">
          <div id="share-code" aria-label={"Access code #{@link.code}"} class="flex gap-1.5">
            <span
              :for={digit <- String.graphemes(@link.code)}
              aria-hidden="true"
              class="flex h-15 w-12 items-center justify-center rounded-field bg-ks-amber-soft font-mono text-[28px] text-base-content"
            >
              {digit}
            </span>
          </div>
          <span id="share-code-text" class="sr-only">{@link.code}</span>
          <div class="flex gap-2">
            <.button
              id="copy-code"
              type="button"
              phx-click={JS.dispatch("ks:copy", detail: %{from: "#share-code-text"})}
            >
              <span data-copy-label>Copy code</span>
            </.button>
            <.button
              id="change-code"
              type="button"
              phx-click="toggle_edit"
              aria-expanded={to_string(@editing)}
            >
              Change code
            </.button>
          </div>
        </div>

        <div
          :if={@editing}
          id="change-code-panel"
          class="flex flex-col gap-3 rounded-xl border border-base-300 bg-base-200 p-4"
        >
          <div class="flex flex-wrap items-center gap-2.5">
            <.button id="regenerate-code" type="button" variant="secondary" phx-click="regenerate">
              Generate a new code
            </.button>
            <span class="text-sm text-ks-muted">or set your own:</span>
          </div>
          <form id="own-code-form" phx-submit="save_code" class="flex flex-wrap items-center gap-2.5">
            <.code_input id="new-own-code" class="w-[180px] text-lg" />
            <.button id="save-own-code" variant="outline">Save my code</.button>
          </form>
          <.code_hint error={@code_error} />
        </div>
        <span class="text-[13px] text-ks-muted">Changing the code locks out anyone using the old one.</span>
      </div>

      <div class="flex flex-col gap-2 rounded-xl bg-base-200 p-4">
        <span class="text-sm font-bold">Invite message</span>
        <p id="invite-message" class="text-[15px] leading-normal text-base-content/80">{@invite}</p>
        <.button
          id="copy-invite"
          type="button"
          size="sm"
          class="self-start"
          phx-click={JS.dispatch("ks:copy", detail: %{from: "#invite-message"})}
        >
          <span data-copy-label>Copy message</span>
        </.button>
      </div>

      <.button
        id="open-as-guest"
        variant="primary"
        size="lg"
        href={~p"/a/#{@link.slug}"}
        target="_blank"
      >
        Open as a guest
      </.button>
    </section>
    """
  end

  attr :link, ShareLink, default: nil
  attr :form, Phoenix.HTML.Form, required: true
  attr :downloads?, :boolean, required: true, doc: "the plan includes guest downloads"

  defp settings_card(assigns) do
    ~H"""
    <section
      id="share-settings"
      aria-label="Sharing settings"
      class="flex flex-col gap-5 rounded-2xl border border-base-300 bg-base-100 p-7"
    >
      <h2 class="text-xl font-bold">Settings</h2>
      <%= if @link do %>
        <.form
          for={@form}
          id="share-settings-form"
          phx-change="save_settings"
          class="flex flex-col gap-4 [&_.fieldset]:mb-0"
        >
          <.input
            field={@form[:expires_in]}
            type="select"
            label="Link expires"
            options={expiry_options(@link)}
            value={if @link.expires_at, do: "", else: "never"}
          />
          <div class="flex flex-col gap-1.5">
            <.input
              field={@form[:default_view]}
              type="select"
              label="Guests see the album as"
              options={ShareLink.view_options()}
            />
            <span class="text-[13px] text-ks-muted">Guests can still switch between all three.</span>
          </div>
          <.toggle field={@form[:show_details]} label="Show captions and locations" />
          <.toggle
            field={@form[:allow_downloads]}
            label="Let guests download photos"
            disabled={not @downloads?}
          />
          <.link
            :if={not @downloads?}
            id="downloads-upgrade"
            navigate={~p"/billing"}
            class="-mt-2 text-[13px] text-ks-muted no-underline hover:text-primary"
          >
            Guest downloads come with Plus and Pro.
            <span class="font-bold text-primary">See plans</span>
          </.link>
        </.form>
      <% else %>
        <p class="text-sm text-ks-muted">
          Expiry, how guests first see the album, captions and downloads can be set once the link exists.
        </p>
      <% end %>

      <label class="flex items-center justify-between gap-3 text-[15px] text-ks-muted">
        <span>
          Background music in the slideshow
          <.badge variant="muted" class="ml-1">Coming soon</.badge>
        </span>
        <input
          type="checkbox"
          disabled
          class="toggle toggle-sm"
          aria-label="Background music (coming soon)"
        />
      </label>

      <%= if @link do %>
        <div id="share-activity" class="flex flex-col gap-1 border-t border-base-300 pt-4">
          <span class="text-sm font-bold">Activity</span>
          <span class="text-sm text-ks-muted">{activity(@link)}</span>
        </div>
        <.button
          id="turn-off-sharing"
          type="button"
          variant="danger"
          class="self-start"
          phx-click="unshare"
          data-confirm="Turn off sharing? The link and code stop working for everyone."
        >
          Turn off sharing
        </.button>
      <% end %>
    </section>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :disabled, :boolean, default: false

  defp toggle(assigns) do
    assigns =
      assign(
        assigns,
        :checked,
        Phoenix.HTML.Form.normalize_value("checkbox", assigns.field.value)
      )

    ~H"""
    <label
      for={@field.id}
      class={[
        "flex items-center justify-between gap-3 text-[15px]",
        if(@disabled, do: "text-ks-muted", else: "cursor-pointer")
      ]}
    >
      {@label}
      <input type="hidden" name={@field.name} value="false" />
      <input
        type="checkbox"
        id={@field.id}
        name={@field.name}
        value="true"
        checked={@checked and not @disabled}
        disabled={@disabled}
        class="toggle toggle-primary toggle-sm"
      />
    </label>
    """
  end

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope
    album = Albums.get_album_by_slug!(scope, slug)
    link = Sharing.get_link(scope, album)

    {:ok,
     socket
     |> OwnerShell.put_current_album(album.id)
     |> assign(
       page_title: "Share · #{album.name}",
       album: album,
       mode: "auto",
       editing: false,
       code_error: nil,
       downloads?: Entitlements.can?(scope, :guest_downloads)
     )
     |> assign_link(link)}
  end

  @impl true
  def handle_event("pick_mode", %{"mode" => mode}, socket) when mode in ~w(auto manual),
    do: {:noreply, assign(socket, mode: mode, code_error: nil)}

  def handle_event("pick_mode", _params, socket), do: {:noreply, socket}

  def handle_event("create", params, socket) do
    %{current_scope: scope, album: album} = socket.assigns

    case Sharing.create_link(scope, album, params["mode"] || socket.assigns.mode, params["code"]) do
      {:ok, link} ->
        {:noreply,
         socket
         |> assign(code_error: nil)
         |> assign_link(link)
         |> put_flash(:info, "Your album is shared.")}

      {:error, message} when is_binary(message) ->
        {:noreply, assign(socket, code_error: message)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, socket |> assign_link(Sharing.get_link(scope, album))}
    end
  end

  def handle_event("toggle_edit", _params, socket),
    do: {:noreply, assign(socket, editing: not socket.assigns.editing, code_error: nil)}

  def handle_event("regenerate", _params, socket), do: change_code(socket, "auto", nil)

  def handle_event("save_code", %{"code" => code}, socket),
    do: change_code(socket, "manual", code)

  def handle_event("save_settings", %{"share_link" => params}, socket) do
    case Sharing.update_settings(socket.assigns.current_scope, socket.assigns.link, params) do
      {:ok, link} -> {:noreply, assign_link(socket, link)}
      {:error, changeset} -> {:noreply, assign(socket, settings_form: to_form(changeset))}
    end
  end

  def handle_event("unshare", _params, socket) do
    {:ok, _} = Sharing.delete_link(socket.assigns.current_scope, socket.assigns.link)

    {:noreply,
     socket
     |> assign(editing: false, mode: "auto")
     |> assign_link(nil)
     |> put_flash(:info, "Sharing is off. The old link and code no longer work.")}
  end

  defp change_code(socket, mode, code) do
    case Sharing.change_code(socket.assigns.current_scope, socket.assigns.link, mode, code) do
      {:ok, link} ->
        {:noreply,
         socket
         |> assign(editing: false, code_error: nil)
         |> assign_link(link)
         |> put_flash(:info, "New code saved. Anyone using the old one will need this code.")}

      {:error, message} ->
        {:noreply, assign(socket, code_error: message)}
    end
  end

  defp assign_link(socket, nil),
    do: assign(socket, link: nil, settings_form: to_form(%{}, as: :share_link))

  # The form shows the stored expiry date, not the "in N days" just picked
  defp assign_link(socket, link) do
    link = %{link | expires_in: nil}
    assign(socket, link: link, settings_form: to_form(Sharing.change_settings(link)))
  end

  # "Never/7/30 days", plus the current date when an expiry is set
  defp expiry_options(%ShareLink{expires_at: nil}), do: ShareLink.expiry_options()

  defp expiry_options(%ShareLink{expires_at: at}),
    do: [{"Expires #{Calendar.strftime(at, "%-d %b %Y")}", ""} | ShareLink.expiry_options()]

  defp activity(%ShareLink{open_count: 0}), do: "Not opened yet"

  defp activity(%ShareLink{open_count: count, last_opened_at: at}) do
    times = if count == 1, do: "Opened once", else: "Opened #{count} times"
    "#{times} · last opened #{time_ago(at)}"
  end

  defp time_ago(at) do
    seconds = DateTime.diff(DateTime.utc_now(), at)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> plural(div(seconds, 60), "minute") <> " ago"
      seconds < 86_400 -> plural(div(seconds, 3600), "hour") <> " ago"
      true -> plural(div(seconds, 86_400), "day") <> " ago"
    end
  end

  defp plural(1, unit), do: "1 #{unit}"
  defp plural(n, unit), do: "#{n} #{unit}s"
end
