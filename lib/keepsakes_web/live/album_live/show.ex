defmodule KeepsakesWeb.AlbumLive.Show do
  @moduledoc """
  One album, in three live actions that share this process so uploads
  started on the album page keep going on the upload screen:

    * `:show` (`/app/albums/:slug`) - AlbumNoPhotos or the Album grid
    * `:upload` (`/app/albums/:slug/upload`) - Upload one / Bulk upload:
      `UploadQueue` + `MemoryForm`, Prev/Next, Save or Cancel
    * `:edit` (`/app/albums/:slug/memories/:id`) - the memory editor dialog

  Each file becomes a draft memory as soon as it finishes uploading and is
  optimised in the background (`Keepsakes.Media.ProcessMemory`); the page
  updates live from the owner's PubSub topic. Edits save as you type.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.MemoryComponents

  alias Keepsakes.{Albums, Entitlements, Settings}
  alias Keepsakes.Albums.Memory
  alias Keepsakes.Sharing.Engagement
  alias KeepsakesWeb.OwnerShell

  @accept ~w(.jpg .jpeg .png .heic .heif .webp)
  @max_entries 50

  @impl true
  def render(%{live_action: :upload} = assigns) do
    # Derived at render time: consumed upload entries leave the config only
    # on the next render, so counts assigned in callbacks would lag behind
    entries = Enum.filter(assigns.uploads.photos.entries, & &1.valid?)

    assigns =
      assign(assigns,
        queue_count: length(assigns.drafts) + length(entries),
        status: status(assigns.drafts, entries)
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} owner={@owner}>
      <.upload_input upload={@uploads.photos} />

      <div class="flex flex-col gap-5">
        <div class="flex flex-col gap-1.5">
          <.link
            id="upload-back"
            navigate={@base}
            class="w-fit text-sm font-medium no-underline"
          >
            ← {@album.name}
          </.link>
          <h1 id="upload-title" class="text-[32px] font-bold">
            {if @queue_count > 1,
              do: "Review #{@queue_count} photos before uploading",
              else: "Add a memory"}
          </h1>
          <p class="text-[15px] text-ks-muted">
            {if @queue_count > 1,
              do: "Pick a photo from the list and fill in its details. Name and date are required.",
              else:
                "Name and date are required. Add more photos to the list to upload several at once."}
          </p>
        </div>

        <.limit_notice notice={@limit_notice} />

        <%= if @queue_count == 0 do %>
          <.drop_zone upload={@uploads.photos} max_upload_mb={@max_upload_mb} long_edge={@long_edge} />
        <% else %>
          <div class="grid items-start gap-6 lg:grid-cols-[minmax(260px,300px)_minmax(0,1fr)]">
            <.upload_queue
              drafts={@drafts}
              upload={@uploads.photos}
              selected_id={@selected && @selected.id}
            />

            <div class="flex min-w-0 flex-col gap-3.5">
              <%= if @selected do %>
                <.memory_form
                  form={@form}
                  memory={@selected}
                  index={selected_index(@drafts, @selected) + 1}
                  count={length(@drafts)}
                  cover={@album.cover_memory_id == @selected.id}
                  long_edge={@long_edge}
                />
              <% else %>
                <div class="flex min-h-[320px] items-center justify-center rounded-2xl border border-base-300 bg-base-100 text-ks-muted">
                  <span class="loading loading-spinner loading-md mr-3 text-primary"></span>
                  Uploading…
                </div>
              <% end %>

              <nav
                :if={length(@drafts) > 1}
                id="memory-nav"
                aria-label="Move between photos"
                class="flex items-center justify-between gap-3"
              >
                <.button id="memory-prev" type="button" phx-click="prev">
                  <.icon name="hero-chevron-left" class="size-[18px]" /> Previous
                </.button>
                <div class="flex flex-wrap justify-center gap-1.5" aria-hidden="true">
                  <span
                    :for={draft <- @drafts}
                    class={[
                      "h-2 rounded transition-all duration-300",
                      cond do
                        @selected && draft.id == @selected.id -> "w-[22px] bg-primary"
                        Memory.ready?(draft) -> "w-2 bg-ks-teal-mist"
                        true -> "w-2 bg-accent"
                      end
                    ]}
                  ></span>
                </div>
                <.button id="memory-next" type="button" phx-click="next">
                  Next <.icon name="hero-chevron-right" class="size-[18px]" />
                </.button>
              </nav>
            </div>
          </div>
        <% end %>

        <div
          id="upload-status"
          class="flex flex-wrap items-center justify-between gap-4 rounded-box border border-base-300 bg-base-100 px-5 py-4"
        >
          <span class={["text-[15px] font-medium", status_class(@status)]}>{status_text(@status)}</span>
          <div class="flex gap-2.5">
            <.button id="upload-cancel" type="button" phx-click="discard">Cancel</.button>
            <.button
              id="upload-save"
              type="button"
              variant="primary"
              phx-click="publish"
              phx-disable-with="Saving…"
              disabled={not can_publish?(@status)}
            >
              {if length(@drafts) > 1, do: "Upload #{length(@drafts)} photos", else: "Save to album"}
            </.button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} owner={@owner}>
      <.upload_input upload={@uploads.photos} />

      <div class="flex flex-col gap-6">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div class="flex flex-col gap-1.5">
            <h1 id="album-title" class="text-4xl font-bold">{@album.name}</h1>
            <p id="album-subtitle" class="text-[15px] text-ks-muted">{subtitle(@stats)}</p>
            <p :if={@role != :owner} id="album-shared-by" class="text-sm text-ks-muted">
              Shared by {Keepsakes.Accounts.User.full_name(@album.user)} · you're
              <.badge>{if @role == :editor, do: "an editor", else: "a viewer"}</.badge>
            </p>
          </div>
          <div :if={@role == :owner} class="flex flex-col items-end gap-1.5">
            <div class="flex flex-wrap gap-2.5">
              <.button id="album-people" navigate={~p"/app/albums/#{@album.slug}/people"}>
                <.icon name="hero-user-group" class="size-[18px]" /> People
              </.button>
              <.button id="album-template" navigate={~p"/app/albums/#{@album.slug}/template"}>
                <.icon name="hero-swatch" class="size-[18px]" /> Template
              </.button>
              <%= if @stats.count > 0 do %>
                <.button id="preview-as-guest" href={~p"/a/preview/#{@album.slug}/timeline"}>
                  Preview as guest
                </.button>
                <.button
                  id="share-album"
                  variant="primary"
                  navigate={~p"/app/albums/#{@album.slug}/share"}
                >
                  <.icon name="hero-link" class="size-[18px]" /> Share album
                </.button>
              <% else %>
                <.button id="share-album" type="button" variant="primary" disabled>
                  <.icon name="hero-link" class="size-[18px]" /> Share album
                </.button>
              <% end %>
            </div>
            <span :if={@stats.count == 0} class="text-[13px] text-ks-muted">
              Add at least one photo to share
            </span>
          </div>
          <.button
            :if={@role != :owner}
            id="leave-album"
            type="button"
            phx-click="leave_album"
            data-confirm="Leave this album? You'll need a new invitation to come back."
          >
            Leave album
          </.button>
        </div>

        <.limit_notice notice={@limit_notice} />

        <.review_queue submitted={@submitted} pending_notes={@pending_notes} />

        <.link
          :if={@drafts != []}
          id="resume-upload"
          patch={@base <> "/upload"}
          class="flex items-center justify-between gap-3 rounded-box border border-ks-amber-soft bg-ks-amber-soft px-5 py-3.5 text-[15px] text-ks-amber-deep no-underline"
        >
          <span>
            {ngettext(
              "1 photo is waiting for its details.",
              "%{count} photos are waiting for their details.",
              length(@drafts)
            )}
          </span>
          <span class="font-bold">Continue →</span>
        </.link>

        <%= if @stats.count == 0 and not @can_edit? do %>
          <p id="album-empty-viewer" class="text-ks-muted">No photos in this album yet.</p>
        <% end %>
        <%= if @stats.count == 0 and @can_edit? do %>
          <.drop_zone upload={@uploads.photos} max_upload_mb={@max_upload_mb} long_edge={@long_edge} />
          <div class="flex flex-col gap-3.5">
            <span class="text-sm font-bold text-ks-muted">
              Your memories will line up here, oldest first
            </span>
            <div class="grid gap-5 sm:grid-cols-3" aria-hidden="true">
              <div
                :for={_ <- 1..3}
                class="flex h-[150px] items-end rounded-box border-2 border-dashed border-ks-placeholder p-3.5"
              >
                <span class="font-mono text-[13px] text-ks-field">Month 20XX</span>
              </div>
            </div>
          </div>
        <% end %>
        <%= if @stats.count > 0 do %>
          <section
            :if={@can_edit?}
            id="upload-bar"
            aria-label="Upload photos"
            phx-drop-target={@uploads.photos.ref}
            class="grid items-center gap-6 rounded-2xl border-2 border-dashed border-ks-field bg-base-100 px-7 py-6 transition-colors sm:grid-cols-[minmax(0,1fr)_auto] [&.phx-drop-target-active]:border-primary [&.phx-drop-target-active]:bg-ks-teal-tint"
          >
            <div class="flex items-center gap-4.5">
              <div class="flex size-14 shrink-0 items-center justify-center rounded-[14px] bg-ks-amber-soft">
                <.icon name="hero-arrow-up-tray" class="size-[26px] text-ks-amber-deep" />
              </div>
              <div class="flex flex-col gap-1">
                <div class="text-[17px] font-bold">Drag photos here, or choose how to add them</div>
                <div class="text-sm text-ks-muted">
                  JPG, PNG, HEIC or WebP · max {@max_upload_mb} MB each · resized to {@long_edge} px on the long edge and compressed to save space
                </div>
              </div>
            </div>
            <div class="flex gap-2.5">
              <.upload_label id="upload-one" upload={@uploads.photos} variant="outline">
                Upload one
              </.upload_label>
              <.upload_label id="upload-bulk" upload={@uploads.photos} variant="dark">
                Bulk upload
              </.upload_label>
            </div>
          </section>

          <div id="memories" phx-update="stream" class="grid gap-5 sm:grid-cols-2 xl:grid-cols-3">
            <.memory_card
              :for={{dom_id, memory} <- @streams.memories}
              id={dom_id}
              memory={memory}
              cover={@album.cover_memory_id == memory.id}
              hearts={Map.get(@hearts, memory.id, 0)}
              patch={if(@can_edit?, do: "#{@base}/memories/#{memory.id}")}
            />
          </div>
        <% end %>

        <.guestbook_notes notes={@notes} can_edit?={@can_edit?} />
      </div>

      <.modal
        :if={@live_action == :edit && @selected}
        id="edit-memory-dialog"
        title="Edit memory"
        show
        on_cancel={JS.patch(@base)}
        box_class="max-w-[860px]"
      >
        <.memory_form
          form={@form}
          memory={@selected}
          cover={@album.cover_memory_id == @selected.id}
          long_edge={@long_edge}
          framed={false}
        />
        <section
          :if={@time_capsule?}
          id="memory-time-capsule"
          class="flex flex-col gap-1.5 rounded-box border border-base-300 p-4"
        >
          <h3 class="font-bold">Time capsule</h3>
          <KeepsakesWeb.TimeCapsule.reveal_form
            id="memory-reveal-form"
            event="seal_memory"
            reveal_at={@selected.reveal_at}
            hint="Guests see a sealed photo until then. You and your collaborators always see it."
          />
        </section>
        <div class="flex flex-wrap justify-between gap-2.5">
          <.button
            id="delete-memory"
            type="button"
            variant="danger"
            phx-click="delete_memory"
            data-confirm="Delete this memory? The photo is removed for good."
          >
            <.icon name="hero-trash" class="size-4" /> Delete
          </.button>
          <.button id="edit-done" variant="primary" patch={@base}>Done</.button>
        </div>
      </.modal>
    </Layouts.app>
    """
  end

  attr :submitted, :list, required: true
  attr :pending_notes, :list, required: true

  # Guest photos and guestbook notes waiting for the owner or an editor
  defp review_queue(assigns) do
    ~H"""
    <section
      :if={@submitted != [] or @pending_notes != []}
      id="review-queue"
      aria-label="Waiting for approval"
      class="flex flex-col gap-4 rounded-2xl border border-ks-amber-soft bg-ks-amber-soft/40 p-5"
    >
      <div :if={@submitted != []} id="review-photos" class="flex flex-col gap-3">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="text-lg font-bold">
            {ngettext(
              "1 guest photo is waiting for approval",
              "%{count} guest photos are waiting for approval",
              length(@submitted)
            )}
          </h2>
          <.button
            :if={length(@submitted) > 1}
            id="approve-all-photos"
            size="sm"
            variant="primary"
            phx-click="approve_all_photos"
          >
            Approve all
          </.button>
        </div>
        <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <article
            :for={memory <- @submitted}
            id={"submitted-#{memory.id}"}
            class="flex flex-col overflow-hidden rounded-box border border-base-300 bg-base-100"
          >
            <div class="h-[150px]">
              <.photo memory={memory} width={480} alt={memory.title || ""} class="size-full" />
            </div>
            <div class="flex flex-col gap-1 p-3">
              <span class="font-bold">{memory.title || "Untitled photo"}</span>
              <span class="text-[13px] text-ks-muted">
                From {memory.guest_name}{if Memory.date_label(memory),
                  do: " · #{Memory.date_label(memory)}"}
              </span>
              <p :if={memory.caption} class="line-clamp-2 text-sm text-ks-muted">{memory.caption}</p>
              <div class="mt-1.5 flex gap-2">
                <.button
                  id={"approve-photo-#{memory.id}"}
                  size="sm"
                  variant="primary"
                  phx-click="approve_photo"
                  phx-value-id={memory.id}
                >
                  Approve
                </.button>
                <.button
                  id={"decline-photo-#{memory.id}"}
                  size="sm"
                  phx-click="decline_photo"
                  phx-value-id={memory.id}
                  data-confirm="Decline this photo? It's deleted for good."
                >
                  Decline
                </.button>
              </div>
            </div>
          </article>
        </div>
      </div>

      <div :if={@pending_notes != []} id="review-notes" class="flex flex-col gap-3">
        <h2 class="text-lg font-bold">
          {ngettext(
            "1 guestbook note is waiting for approval",
            "%{count} guestbook notes are waiting for approval",
            length(@pending_notes)
          )}
        </h2>
        <article
          :for={note <- @pending_notes}
          id={"pending-note-#{note.id}"}
          class="flex flex-col gap-2 rounded-box border border-base-300 bg-base-100 p-4"
        >
          <p class="whitespace-pre-line text-[15px]">{note.message}</p>
          <div class="flex flex-wrap items-center justify-between gap-2">
            <span class="text-sm text-ks-muted">— {note.name}</span>
            <div class="flex gap-2">
              <.button
                id={"approve-note-#{note.id}"}
                size="sm"
                variant="primary"
                phx-click="approve_note"
                phx-value-id={note.id}
              >
                Approve
              </.button>
              <.button
                id={"decline-note-#{note.id}"}
                size="sm"
                phx-click="delete_note"
                phx-value-id={note.id}
              >
                Decline
              </.button>
            </div>
          </div>
        </article>
      </div>
    </section>
    """
  end

  attr :notes, :list, required: true
  attr :can_edit?, :boolean, required: true

  # Approved guestbook notes, as guests see them
  defp guestbook_notes(assigns) do
    ~H"""
    <section :if={@notes != []} id="album-guestbook" class="flex flex-col gap-3">
      <h2 class="text-lg font-bold">Guestbook</h2>
      <article
        :for={note <- @notes}
        id={"note-#{note.id}"}
        class="flex flex-col gap-1.5 rounded-box border border-base-300 bg-base-100 p-4"
      >
        <p class="whitespace-pre-line text-[15px]">{note.message}</p>
        <div class="flex items-center justify-between gap-2">
          <span class="text-sm text-ks-muted">— {note.name}</span>
          <button
            :if={@can_edit?}
            id={"remove-note-#{note.id}"}
            type="button"
            phx-click="delete_note"
            phx-value-id={note.id}
            data-confirm="Remove this note from the guestbook?"
            class="cursor-pointer text-sm text-ks-muted underline hover:text-error"
          >
            Remove
          </button>
        </div>
      </article>
    </section>
    """
  end

  attr :upload, Phoenix.LiveView.UploadConfig, required: true

  # The one file input; the drop zones and buttons are labels for it
  defp upload_input(assigns) do
    ~H"""
    <form id="upload-form" phx-change="validate_upload" phx-submit="validate_upload">
      <.live_file_input upload={@upload} class="sr-only" />
    </form>
    """
  end

  attr :id, :string, required: true
  attr :upload, Phoenix.LiveView.UploadConfig, required: true
  attr :variant, :string, values: ~w(outline dark primary), default: "outline"
  attr :size, :string, default: "md"
  slot :inner_block, required: true

  defp upload_label(assigns) do
    ~H"""
    <label
      id={@id}
      for={@upload.ref}
      class={[
        "btn rounded-field font-bold shadow-none transition-colors",
        if(@size == "lg", do: "btn-lg min-h-12 px-5", else: "min-h-11 px-4"),
        case @variant do
          "outline" -> "btn-outline btn-primary"
          "dark" -> "btn-secondary"
          "primary" -> "btn-primary hover:bg-ks-teal-hover"
        end
      ]}
    >
      {render_slot(@inner_block)}
    </label>
    """
  end

  attr :upload, Phoenix.LiveView.UploadConfig, required: true
  attr :max_upload_mb, :integer, required: true
  attr :long_edge, :integer, required: true

  defp drop_zone(assigns) do
    ~H"""
    <section
      id="drop-zone"
      aria-label="Upload photos"
      phx-drop-target={@upload.ref}
      class="flex flex-col items-center gap-5.5 rounded-[20px] border-2 border-dashed border-ks-field bg-base-100 px-8 py-14 text-center transition-colors [&.phx-drop-target-active]:border-primary [&.phx-drop-target-active]:bg-ks-teal-tint"
    >
      <div class="flex size-[72px] items-center justify-center rounded-[18px] bg-ks-amber-soft">
        <.icon name="hero-arrow-up-tray" class="size-8 text-ks-amber-deep" />
      </div>
      <div class="flex max-w-[520px] flex-col gap-2">
        <h2 class="text-[26px] font-bold">Add your first memory</h2>
        <p class="text-base leading-normal text-ks-muted">
          Drag photos here or pick how to add them. Each one gets a name, month and year, and a caption.
        </p>
      </div>
      <div class="flex flex-wrap justify-center gap-2.5">
        <.upload_label id="drop-upload-one" upload={@upload} variant="outline" size="lg">
          Upload one photo
        </.upload_label>
        <.upload_label id="drop-upload-several" upload={@upload} variant="primary" size="lg">
          Upload several
        </.upload_label>
      </div>
      <span class="text-[13px] text-ks-muted">
        JPG, PNG, HEIC or WebP · max {@max_upload_mb} MB each · resized to {@long_edge} px to save space
      </span>
      <p :for={err <- upload_errors(@upload)} class="text-sm text-error">{upload_error_text(err)}</p>
    </section>
    """
  end

  attr :notice, :string, default: nil

  # Why the last photo didn't go in (a plan limit), with the way out
  defp limit_notice(assigns) do
    ~H"""
    <div
      :if={@notice}
      id="limit-notice"
      role="alert"
      class="flex flex-wrap items-center justify-between gap-3 rounded-box border border-ks-amber-soft bg-ks-amber-soft px-5 py-3.5 text-[15px] text-ks-amber-deep"
    >
      <span class="flex items-center gap-2">
        <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
        {@notice}
      </span>
      <div class="flex items-center gap-2">
        <.button
          id="limit-notice-plans"
          size="sm"
          variant="outline"
          navigate={~p"/app/settings/billing"}
        >
          See plans
        </.button>
        <button
          type="button"
          phx-click="dismiss_limit_notice"
          aria-label="Dismiss"
          class="flex size-8 cursor-pointer items-center justify-center rounded-full hover:bg-base-100/50"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope
    album = load_album(scope, params)
    role = Albums.role(scope, album)
    # Collaborators upload against the owner's plan
    max_upload_mb = Entitlements.max_upload_mb(Albums.owner_scope(album))

    if connected?(socket) do
      # The owner gets memory events on their own topic (OwnerShell)
      if role != :owner, do: Albums.subscribe_album(album)
      # Hearts as guests leave them
      Engagement.subscribe(album)
    end

    socket =
      socket
      |> OwnerShell.put_current_album(album.id)
      |> assign(
        album: album,
        role: role,
        can_edit?: Albums.allows?(role, :edit),
        base: base_path(role, album),
        page_title: album.name,
        long_edge: Settings.get(:image_long_edge),
        max_upload_mb: max_upload_mb,
        time_capsule?: Entitlements.can?(album.user_id, :time_capsule),
        limit_notice: nil,
        selected: nil,
        form: nil
      )
      |> load_memories()
      |> load_review()
      |> assign_drafts(
        if Albums.allows?(role, :edit), do: Albums.list_drafts(scope, album), else: []
      )
      |> allow_upload(:photos,
        accept: @accept,
        max_entries: @max_entries,
        max_file_size: max_upload_mb * 1_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )

    {:ok, socket}
  end

  # /app/albums/:slug for the owner, /app/shared/:id for collaborators
  defp load_album(scope, %{"slug" => slug}), do: Albums.get_album_by_slug!(scope, slug)
  defp load_album(scope, %{"album_id" => id}), do: Albums.get_shared_album!(scope, id)

  defp reload_album(%{assigns: %{current_scope: scope, album: album, role: :owner}}),
    do: Albums.get_album_by_slug!(scope, album.slug)

  defp reload_album(%{assigns: %{current_scope: scope, album: album}}),
    do: Albums.get_shared_album!(scope, album.id)

  defp base_path(:owner, album), do: ~p"/app/albums/#{album.slug}"
  defp base_path(_role, album), do: ~p"/app/shared/#{album.id}"

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, apply_action(socket, socket.assigns.live_action, params)}

  defp apply_action(socket, :show, _params),
    do: assign(socket, page_title: socket.assigns.album.name, selected: nil, form: nil)

  # Viewers only look
  defp apply_action(%{assigns: %{can_edit?: false}}, action, _params)
       when action in [:upload, :edit],
       do: raise(Keepsakes.Albums.NotAllowed)

  defp apply_action(socket, :upload, _params) do
    %{drafts: drafts, selected: selected} = socket.assigns

    socket = assign(socket, page_title: "Add a memory · #{socket.assigns.album.name}")

    cond do
      selected && Enum.any?(drafts, &(&1.id == selected.id)) -> socket
      drafts != [] -> select(socket, hd(drafts))
      true -> assign(socket, selected: nil, form: nil)
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    memory = Albums.get_memory!(socket.assigns.current_scope, socket.assigns.album, id)
    socket |> assign(page_title: memory.title || "Edit memory") |> select(memory)
  end

  ## Uploads

  @impl true
  def handle_event("validate_upload", _params, socket),
    do: {:noreply, open_upload_screen(socket)}

  def handle_event("cancel_entry", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :photos, ref)}

  def handle_event("dismiss_limit_notice", _params, socket),
    do: {:noreply, assign(socket, limit_notice: nil)}

  ## Queue navigation

  def handle_event("select_memory", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.drafts, &(&1.id == id)) do
      nil -> {:noreply, socket}
      memory -> {:noreply, select(socket, memory)}
    end
  end

  def handle_event(direction, _params, %{assigns: %{drafts: [_, _ | _] = drafts}} = socket)
      when direction in ["prev", "next"] do
    step = if direction == "next", do: 1, else: -1

    index =
      rem(selected_index(drafts, socket.assigns.selected) + step + length(drafts), length(drafts))

    {:noreply, select(socket, Enum.at(drafts, index))}
  end

  def handle_event(direction, _params, socket) when direction in ["prev", "next"],
    do: {:noreply, socket}

  ## Memory form

  def handle_event(
        "save_memory",
        %{"memory" => params},
        %{assigns: %{selected: %Memory{}}} = socket
      ) do
    %{current_scope: scope, selected: memory} = socket.assigns

    case Albums.update_memory(scope, memory, Map.drop(params, ["cover"])) do
      {:ok, memory} ->
        {:noreply,
         socket |> put_memory(memory) |> select(memory) |> apply_cover(memory, params["cover"])}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
    end
  end

  def handle_event(
        "add_person",
        %{"person" => name},
        %{assigns: %{selected: %Memory{} = memory}} = socket
      ) do
    if String.trim(name) == "",
      do: {:noreply, socket},
      else: set_people(socket, memory.people ++ [name])
  end

  def handle_event(
        "remove_person",
        %{"index" => index},
        %{assigns: %{selected: %Memory{} = memory}} = socket
      ) do
    set_people(socket, List.delete_at(memory.people, String.to_integer(index)))
  end

  ## Save / cancel / delete

  def handle_event("publish", _params, socket) do
    %{current_scope: scope, album: album} = socket.assigns
    {:ok, count} = Albums.publish_drafts(scope, album)

    {:noreply,
     socket
     |> assign(album: reload_album(socket))
     |> assign_drafts([])
     |> load_memories()
     |> put_flash(
       :info,
       ngettext(
         "1 memory added to the timeline.",
         "%{count} memories added to the timeline.",
         count
       )
     )
     |> push_patch(to: socket.assigns.base)}
  end

  def handle_event("discard", _params, socket) do
    %{current_scope: scope, album: album} = socket.assigns

    socket =
      Enum.reduce(
        socket.assigns.uploads.photos.entries,
        socket,
        &cancel_upload(&2, :photos, &1.ref)
      )

    {:ok, _} = Albums.discard_drafts(scope, album)

    {:noreply,
     socket
     |> assign(album: reload_album(socket))
     |> assign_drafts([])
     |> push_patch(to: socket.assigns.base)}
  end

  def handle_event("delete_memory", _params, %{assigns: %{selected: %Memory{} = memory}} = socket) do
    {:ok, _} = Albums.delete_memory(socket.assigns.current_scope, memory)

    {:noreply,
     socket
     |> assign(album: reload_album(socket))
     |> load_memories()
     |> put_flash(:info, "Memory deleted.")
     |> push_patch(to: socket.assigns.base)}
  end

  def handle_event("leave_album", _params, %{assigns: %{role: role}} = socket)
      when role in [:editor, :viewer] do
    :ok = Keepsakes.Albums.Members.leave(socket.assigns.current_scope, socket.assigns.album)

    {:noreply,
     socket
     |> put_flash(:info, "You left #{socket.assigns.album.name}.")
     |> push_navigate(to: ~p"/app/albums")}
  end

  ## Time capsule (memory editor)

  def handle_event("seal_memory", params, %{assigns: %{selected: %Memory{} = memory}} = socket) do
    case params |> KeepsakesWeb.TimeCapsule.params() |> KeepsakesWeb.TimeCapsule.parse() do
      {:ok, reveal_at} ->
        case Albums.set_memory_reveal(socket.assigns.current_scope, memory, reveal_at) do
          {:ok, memory} ->
            {:noreply,
             socket
             |> put_memory(memory)
             |> select(memory)
             |> put_flash(
               :info,
               if(reveal_at,
                 do: "Sealed until #{KeepsakesWeb.TimeCapsule.label(reveal_at)}.",
                 else: "Unsealed."
               )
             )}

          {:error, :not_in_plan} ->
            {:noreply, put_flash(socket, :error, "Time capsules aren't included in this plan.")}
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  ## Guest photos and guestbook notes waiting for approval

  def handle_event("approve_photo", %{"id" => id}, socket) do
    %{current_scope: scope, album: album} = socket.assigns
    memory = Albums.get_memory!(scope, album, id)
    {:ok, _} = Albums.approve_submitted(scope, album, [memory])

    {:noreply,
     socket
     |> load_memories()
     |> load_review()
     |> put_flash(:info, "Photo added to the timeline.")}
  end

  def handle_event("approve_all_photos", _params, socket) do
    %{current_scope: scope, album: album} = socket.assigns
    {:ok, count} = Albums.approve_submitted(scope, album)

    {:noreply,
     socket
     |> load_memories()
     |> load_review()
     |> put_flash(:info, ngettext("1 photo added.", "%{count} photos added.", count))}
  end

  def handle_event("decline_photo", %{"id" => id}, socket) do
    %{current_scope: scope, album: album} = socket.assigns
    memory = Albums.get_memory!(scope, album, id)
    {:ok, _} = Albums.delete_memory(scope, memory)
    {:noreply, socket |> load_review() |> put_flash(:info, "Photo declined.")}
  end

  def handle_event("approve_note", %{"id" => id}, socket) do
    %{current_scope: scope, album: album} = socket.assigns
    {:ok, _} = Engagement.approve_note(scope, album, id)
    {:noreply, load_review(socket)}
  end

  def handle_event("delete_note", %{"id" => id}, socket) do
    %{current_scope: scope, album: album} = socket.assigns
    {:ok, _} = Engagement.delete_note(scope, album, id)
    {:noreply, socket |> load_review() |> put_flash(:info, "Note removed.")}
  end

  defp handle_progress(:photos, entry, socket) do
    socket = open_upload_screen(socket)

    if entry.done? do
      %{current_scope: scope, album: album} = socket.assigns

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok,
           Albums.create_draft(scope, album, %{
             path: path,
             filename: entry.client_name,
             bytes: entry.client_size
           })}
        end)

      case result do
        {:ok, memory} ->
          socket = put_memory(socket, memory)
          {:noreply, if(socket.assigns.selected, do: socket, else: select(socket, memory))}

        {:error, {:over_limit, _, _, _} = over} ->
          notice = "#{entry.client_name} wasn't added. #{Entitlements.message(over)}"
          {:noreply, assign(socket, limit_notice: notice)}

        {:error, _reason} ->
          {:noreply,
           put_flash(socket, :error, "#{entry.client_name} couldn't be saved. Please try again.")}
      end
    else
      {:noreply, socket}
    end
  end

  ## Live updates (processing results, other tabs)

  @impl true
  def handle_info({event, %Memory{} = memory}, socket)
      when event in [:memory_updated, :memory_deleted] do
    if memory.album_id == socket.assigns.album.id,
      do: {:noreply, apply_event(socket, event, memory)},
      else: {:noreply, socket}
  end

  def handle_info({:guestbook_changed, album_id}, %{assigns: %{album: %{id: album_id}}} = socket),
    do: {:noreply, load_review(socket)}

  def handle_info({:hearts, memory_id, count}, socket) do
    hearts = Map.put(socket.assigns.hearts, memory_id, count)
    memory = Albums.get_memory!(socket.assigns.current_scope, socket.assigns.album, memory_id)
    {:noreply, socket |> assign(hearts: hearts) |> stream_insert(:memories, memory)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # A guest's photo arriving or finishing processing updates the queue
  defp apply_event(socket, _event, %Memory{status: "submitted"}), do: load_review(socket)

  defp apply_event(socket, :memory_updated, memory) do
    socket = put_memory(socket, memory)

    if socket.assigns.selected && socket.assigns.selected.id == memory.id,
      do: select(socket, memory),
      else: socket
  end

  defp apply_event(socket, :memory_deleted, memory) do
    socket
    |> assign_drafts(Enum.reject(socket.assigns.drafts, &(&1.id == memory.id)))
    |> stream_delete(:memories, memory)
    |> assign(submitted: Enum.reject(socket.assigns.submitted, &(&1.id == memory.id)))
  end

  ## Helpers

  # Picking or dropping files on the album page opens the upload screen
  defp open_upload_screen(%{assigns: %{live_action: :upload}} = socket), do: socket

  defp open_upload_screen(socket) do
    if socket.assigns.uploads.photos.entries != [],
      do: push_patch(socket, to: socket.assigns.base <> "/upload"),
      else: socket
  end

  defp select(socket, memory),
    do: assign(socket, selected: memory, form: to_form(Albums.change_memory(memory)))

  # Puts a changed memory where it belongs: the draft list or the grid
  defp put_memory(socket, %Memory{status: "draft"} = memory) do
    drafts = socket.assigns.drafts

    drafts =
      if Enum.any?(drafts, &(&1.id == memory.id)),
        do: Enum.map(drafts, &if(&1.id == memory.id, do: memory, else: &1)),
        else: drafts ++ [memory]

    assign_drafts(socket, drafts)
  end

  # A published memory's date may move the album's date range
  defp put_memory(socket, %Memory{} = memory) do
    memories = Albums.list_memories(socket.assigns.current_scope, socket.assigns.album)

    socket
    |> stream_insert(:memories, memory)
    |> assign(stats: stats(memories))
  end

  defp set_people(socket, people) do
    %{current_scope: scope, selected: memory} = socket.assigns

    case Albums.set_people(scope, memory, people) do
      {:ok, memory} ->
        {:noreply, socket |> put_memory(memory) |> select(memory)}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Names can be up to 40 characters, with up to 20 people per photo."
         )}
    end
  end

  defp apply_cover(socket, memory, cover) do
    %{current_scope: scope, album: album} = socket.assigns

    new_cover =
      case {cover, album.cover_memory_id == memory.id} do
        {"true", false} -> memory
        {"false", true} -> nil
        _ -> :unchanged
      end

    case new_cover do
      :unchanged ->
        socket

      new_cover ->
        previous_id = album.cover_memory_id
        {:ok, album} = Albums.set_cover(scope, album, new_cover)

        socket = assign(socket, album: album)

        # Re-render the published cards whose Cover badge changed
        [previous_id, album.cover_memory_id]
        |> Enum.reject(&(is_nil(&1) or &1 == memory.id))
        |> Enum.map(&Albums.get_memory!(scope, album, &1))
        |> Enum.concat([memory])
        |> Enum.filter(&(&1.status == "published"))
        |> Enum.reduce(socket, &stream_insert(&2, :memories, &1))
    end
  end

  defp load_memories(socket) do
    memories = Albums.list_memories(socket.assigns.current_scope, socket.assigns.album)

    socket
    |> assign(hearts: Engagement.heart_counts(socket.assigns.album))
    |> stream(:memories, memories, reset: true)
    |> assign(stats: stats(memories))
  end

  # Guest photos and notes waiting for approval (owner and editors), and
  # the approved guestbook (everyone with access)
  defp load_review(
         %{assigns: %{current_scope: scope, album: album, can_edit?: can_edit?}} = socket
       ) do
    assign(socket,
      submitted: if(can_edit?, do: Albums.list_submitted(scope, album), else: []),
      pending_notes: if(can_edit?, do: Engagement.pending_notes(scope, album), else: []),
      notes: Engagement.approved_notes(scope, album)
    )
  end

  defp assign_drafts(socket, drafts), do: assign(socket, drafts: drafts)

  defp stats(memories) do
    dated = Enum.filter(memories, &(&1.year && &1.month))

    range =
      case {List.first(dated), List.last(dated)} do
        {nil, _} -> nil
        {first, last} when first.id == last.id -> Memory.short_date_label(first)
        {first, last} -> "#{Memory.short_date_label(first)} – #{Memory.short_date_label(last)}"
      end

    %{count: length(memories), range: range}
  end

  defp subtitle(%{count: 0}), do: "No memories yet"

  defp subtitle(%{count: count, range: range}) do
    [ngettext("1 memory", "%{count} memories", count), range, "Sorted by date taken"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp selected_index(drafts, selected),
    do: Enum.find_index(drafts, &(selected && &1.id == selected.id)) || 0

  # Upload screen footer state
  defp status(_drafts, [_ | _] = entries), do: {:uploading, length(entries)}
  defp status([], []), do: :empty

  defp status([memory], []) do
    if Memory.ready?(memory), do: {:ready_one, Memory.date_label(memory)}, else: :incomplete_one
  end

  defp status(drafts, []) do
    case Enum.count(drafts, &(not Memory.ready?(&1))) do
      0 -> :all_ready
      left -> {:incomplete_many, left}
    end
  end

  defp status_text({:uploading, n}),
    do: ngettext("Uploading 1 photo…", "Uploading %{count} photos…", n)

  defp status_text(:empty), do: "Choose photos to add to this album."

  defp status_text({:ready_one, date}),
    do: "Ready to save. It will sit on the timeline under #{date}."

  defp status_text(:incomplete_one), do: "Add a name, month and year to save this memory."

  defp status_text(:all_ready),
    do: "All photos are ready. They will be placed on the timeline by month and year."

  defp status_text({:incomplete_many, left}) do
    ngettext(
      "1 photo still needs a name or date. You can upload now and finish them later.",
      "%{count} photos still need a name or date. You can upload now and finish them later.",
      left
    )
  end

  defp status_class(:all_ready), do: "text-primary"
  defp status_class({:ready_one, _}), do: "text-primary"
  defp status_class(_status), do: "text-ks-amber-deep"

  defp can_publish?({:ready_one, _}), do: true
  defp can_publish?(:all_ready), do: true
  defp can_publish?({:incomplete_many, _}), do: true
  defp can_publish?(_), do: false
end
