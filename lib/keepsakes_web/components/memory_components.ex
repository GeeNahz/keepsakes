defmodule KeepsakesWeb.MemoryComponents do
  @moduledoc """
  Owner-side memory UI from the canvas: the album grid card, the
  `UploadQueue` sidebar and the `MemoryForm` shared by Upload one, Bulk
  upload and the memory editor.
  """
  use KeepsakesWeb, :html

  alias Keepsakes.Albums.Memory
  alias Keepsakes.Storage

  @tints ~w(bg-ks-tint-sand bg-ks-tint-sage bg-ks-tint-moss bg-ks-tint-sky bg-ks-tint-lilac bg-ks-tint-rose)

  @doc "Placeholder tint for a memory, stable per memory."
  def tint(%Memory{id: id}), do: Enum.at(@tints, :erlang.phash2(id, length(@tints)))

  @doc """
  The photo itself once processed; a tinted placeholder while optimising
  or when processing failed.
  """
  attr :memory, Memory, required: true
  attr :width, :integer, default: 1200, values: [480, 1200, 2400]
  attr :class, :any, default: nil
  attr :alt, :string, default: ""
  attr :compact, :boolean, default: false, doc: "hide the status text (thumbnails)"

  def photo(%{memory: %Memory{processing: "ready"}} = assigns) do
    ~H"""
    <img
      src={Storage.url(Memory.variant_key(@memory, @width))}
      alt={@alt}
      loading="lazy"
      decoding="async"
      class={["object-cover", @class]}
    />
    """
  end

  def photo(assigns) do
    ~H"""
    <div
      class={["flex flex-col items-center justify-center gap-2", tint(@memory), @class]}
      role="img"
      aria-label={
        if(@memory.processing == "failed", do: "Photo failed to process", else: "Optimising photo")
      }
    >
      <%= cond do %>
        <% @memory.processing == "failed" -> %>
          <.icon name="hero-exclamation-triangle" class="size-8 text-error" />
          <span :if={!@compact} class="px-3 text-center text-[13px] text-error">
            {@memory.processing_error}
          </span>
        <% @compact -> %>
          <span class="loading loading-spinner loading-xs text-base-content/40"></span>
        <% true -> %>
          <span class="loading loading-spinner loading-md text-base-content/40"></span>
          <span class="text-[13px] text-base-content/60">Optimising…</span>
      <% end %>
    </div>
    """
  end

  @doc "A memory in the album grid; opens the editor."
  attr :id, :string, required: true
  attr :memory, Memory, required: true
  attr :cover, :boolean, default: false
  attr :patch, :string, required: true

  def memory_card(assigns) do
    ~H"""
    <.link
      id={@id}
      patch={@patch}
      class="group flex flex-col overflow-hidden rounded-box border border-base-300 bg-base-100 text-base-content no-underline transition duration-200 hover:-translate-y-0.5 hover:shadow-[0_14px_30px_rgba(27,30,39,0.10)] focus-visible:ring-4 focus-visible:ring-ks-teal-soft"
    >
      <div class="relative h-[190px] overflow-hidden">
        <.photo
          memory={@memory}
          width={1200}
          alt={@memory.title || ""}
          class="size-full transition-transform duration-500 group-hover:scale-[1.03]"
        />
        <.badge :if={@cover} class="absolute left-2.5 top-2.5">Cover</.badge>
      </div>
      <div class="flex flex-col gap-1.5 p-4">
        <div class="flex items-center justify-between gap-2">
          <span class="font-mono text-[13px] text-ks-muted">
            {Memory.date_label(@memory) || "No date yet"}
          </span>
          <.badge :if={Memory.missing(@memory)} variant="pending" class="shrink-0">
            Needs {Memory.missing(@memory)}
          </.badge>
        </div>
        <div class="text-[17px] font-bold">{@memory.title || "Untitled photo"}</div>
        <p :if={@memory.caption} class="line-clamp-2 text-sm leading-[1.45] text-ks-muted">
          {@memory.caption}
        </p>
        <p :if={place_people(@memory)} class="text-[13px] text-ks-muted">{place_people(@memory)}</p>
      </div>
    </.link>
    """
  end

  defp place_people(%Memory{place: place, people: people}) do
    case Enum.reject([place, Enum.join(people, ", ")], &(&1 in [nil, ""])) do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  @doc """
  The `UploadQueue`: files still uploading, then drafts with readiness
  badges. Selecting a row sends `"select_memory"`.
  """
  attr :drafts, :list, required: true
  attr :upload, Phoenix.LiveView.UploadConfig, required: true
  attr :selected_id, :string, default: nil

  def upload_queue(assigns) do
    total = length(assigns.drafts) + length(assigns.upload.entries)
    ready = Enum.count(assigns.drafts, &Memory.ready?/1)
    assigns = assign(assigns, total: total, ready: ready)

    ~H"""
    <aside
      id="upload-queue"
      aria-label="Photos to upload"
      class="flex flex-col gap-1.5 rounded-2xl border border-base-300 bg-base-100 px-3 pb-3 pt-4"
    >
      <div class="flex flex-col gap-2 px-1.5 pb-2.5">
        <div class="flex items-baseline justify-between">
          <span class="text-[15px] font-bold">Photos ({@total})</span>
          <span id="queue-ready-count" class="text-[13px] text-ks-muted">
            {@ready} of {@total} ready
          </span>
        </div>
        <progress
          class="progress progress-primary h-1.5 w-full bg-base-300"
          value={@ready}
          max={max(@total, 1)}
          aria-label="Photos ready"
        ></progress>
      </div>

      <div
        :for={entry <- @upload.entries}
        id={"upload-entry-#{entry.ref}"}
        class="flex min-h-16 items-center gap-3 rounded-field px-2.5 py-2"
      >
        <span class="flex size-12 shrink-0 items-center justify-center rounded-md bg-base-200">
          <span class="loading loading-spinner loading-sm text-primary"></span>
        </span>
        <span class="flex min-w-0 flex-1 flex-col gap-1.5">
          <span class="truncate font-mono text-xs text-ks-muted">{entry.client_name}</span>
          <progress
            class="progress progress-primary h-1.5 w-full"
            value={entry.progress}
            max="100"
            aria-label={"Uploading #{entry.client_name}"}
          ></progress>
          <span :for={err <- upload_errors(@upload, entry)} class="text-xs text-error">
            {upload_error_text(err)}
          </span>
        </span>
        <button
          type="button"
          phx-click="cancel_entry"
          phx-value-ref={entry.ref}
          aria-label={"Stop uploading #{entry.client_name}"}
          class="btn btn-circle btn-ghost btn-xs"
        >
          <.icon name="hero-x-mark" class="size-3.5" />
        </button>
      </div>

      <button
        :for={memory <- @drafts}
        id={"queue-#{memory.id}"}
        type="button"
        phx-click="select_memory"
        phx-value-id={memory.id}
        aria-pressed={to_string(memory.id == @selected_id)}
        class={[
          "flex min-h-16 w-full cursor-pointer items-center gap-3 rounded-field border-2 px-2.5 py-2 text-left transition-colors",
          if(memory.id == @selected_id,
            do: "border-primary bg-ks-teal-tint",
            else: "border-transparent hover:bg-base-200"
          )
        ]}
      >
        <span class="size-12 shrink-0 overflow-hidden rounded-md">
          <.photo memory={memory} width={480} class="size-12" compact />
        </span>
        <span class="flex min-w-0 flex-1 flex-col gap-0.5">
          <span class="truncate text-[15px] font-bold">{memory.title || "Untitled photo"}</span>
          <span class="truncate font-mono text-xs text-ks-muted">
            {[Memory.short_date_label(memory), memory.original_filename]
            |> Enum.reject(&is_nil/1)
            |> Enum.join(" · ")}
          </span>
        </span>
        <%= if missing = Memory.missing(memory) do %>
          <.badge variant="pending" class="shrink-0">Needs {missing}</.badge>
        <% else %>
          <.badge variant="ready" class="shrink-0">Ready</.badge>
        <% end %>
      </button>

      <p :for={err <- upload_errors(@upload)} class="px-2 text-sm text-error">
        {upload_error_text(err)}
      </p>

      <label
        for={@upload.ref}
        id="queue-add-more"
        class="mt-1.5 flex min-h-11 cursor-pointer items-center justify-center rounded-field border border-dashed border-ks-field font-medium transition-colors hover:border-primary hover:bg-ks-teal-tint"
      >
        + Add more photos
      </label>
    </aside>
    """
  end

  @doc "Human message for a LiveView upload error."
  def upload_error_text(:too_large), do: "That file is larger than the upload limit."
  def upload_error_text(:not_accepted), do: "Only JPG, PNG, HEIC or WebP photos can be added."
  def upload_error_text(:too_many_files), do: "That's more photos than one upload can take."
  def upload_error_text(_), do: "That file couldn't be uploaded."

  @doc """
  The `MemoryForm`: polaroid preview and optimisation note on the left,
  details on the right. Changes send `"save_memory"`; people are added
  with `"add_person"` / removed with `"remove_person"`.
  """
  attr :form, Phoenix.HTML.Form, required: true
  attr :memory, Memory, required: true
  attr :index, :integer, default: 1
  attr :count, :integer, default: 1
  attr :cover, :boolean, default: false
  attr :long_edge, :integer, required: true
  attr :framed, :boolean, default: true, doc: "card border + padding (off inside a dialog)"

  def memory_form(assigns) do
    ~H"""
    <section
      id="memory-details"
      aria-label="Memory details"
      class={[
        "grid items-start gap-7 [grid-template-columns:repeat(auto-fit,minmax(260px,1fr))]",
        @framed && "rounded-2xl border border-base-300 bg-base-100 p-6"
      ]}
    >
      <div class="flex flex-col gap-3.5">
        <div class="-rotate-[1.5deg] rounded-md border border-base-300 bg-white px-3 pb-4 pt-3 text-ks-ink shadow-[0_10px_24px_rgba(27,30,39,0.10)] transition-transform duration-300 hover:rotate-0">
          <.photo memory={@memory} width={1200} class="h-60 w-full" alt={@memory.title || ""} />
          <div class="min-h-11 pt-2.5 font-hand text-[28px] leading-tight">
            {@memory.title || "Untitled photo"}
          </div>
          <div class="font-mono text-xs text-ks-ink-muted">
            {Memory.date_label(@memory) || "No date yet"}
          </div>
        </div>

        <div
          id="optimise-note"
          class={[
            "flex items-start gap-2.5 rounded-xl px-3.5 py-3 text-[13px]",
            if(@memory.processing == "failed", do: "bg-error/10", else: "bg-ks-teal-soft")
          ]}
        >
          <%= case @memory.processing do %>
            <% "ready" -> %>
              <.icon name="hero-check-circle" class="size-5 shrink-0 text-primary" />
              <span class="flex flex-col gap-0.5">
                <span class="font-bold">{@memory.original_filename} optimised</span>
                <span class="text-base-content/80">
                  {Layouts.format_bytes(@memory.original_bytes)} → {Layouts.format_bytes(
                    @memory.stored_bytes
                  )} · {@long_edge} px long edge
                </span>
              </span>
            <% "failed" -> %>
              <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-error" />
              <span class="flex flex-col gap-0.5">
                <span class="font-bold">{@memory.original_filename}</span>
                <span class="text-error">{@memory.processing_error}</span>
              </span>
            <% _ -> %>
              <span class="loading loading-spinner loading-sm shrink-0 text-primary"></span>
              <span class="flex flex-col gap-0.5">
                <span class="font-bold">Optimising {@memory.original_filename}…</span>
                <span class="text-base-content/80">
                  {Layouts.format_bytes(@memory.original_bytes)} · resizing to {@long_edge} px and removing location data
                </span>
              </span>
          <% end %>
        </div>
      </div>

      <div class="flex flex-col gap-4">
        <.form
          for={@form}
          id="memory-form"
          phx-change="save_memory"
          phx-submit="save_memory"
          class="flex flex-col gap-4 [&_.fieldset]:mb-0"
        >
          <div
            :if={@count > 1}
            id="memory-counter"
            class="text-[13px] font-bold uppercase tracking-[0.06em] text-ks-muted"
          >
            Photo {@index} of {@count}
          </div>

          <div class="flex flex-col gap-1.5">
            <label for="memory-title" class="text-sm font-bold">
              Name <span class="text-error">*</span>
            </label>
            <.input
              field={@form[:title]}
              id="memory-title"
              placeholder="e.g. First birthday"
              maxlength="80"
              autocomplete="off"
              phx-debounce="300"
            />
            <span :if={is_nil(@memory.title)} class="text-[13px] text-ks-amber-deep">
              Give this memory a name.
            </span>
          </div>

          <fieldset class="flex flex-col gap-1.5">
            <legend class="pb-1.5 text-sm font-bold">
              Date taken <span class="text-error">*</span>
            </legend>
            <div class="grid grid-cols-2 gap-2.5">
              <.input
                field={@form[:month]}
                id="memory-month"
                type="select"
                prompt="Month"
                aria-label="Month"
                options={month_options()}
              />
              <.input
                field={@form[:year]}
                id="memory-year"
                type="select"
                prompt="Year"
                aria-label="Year"
                options={year_options()}
              />
            </div>
            <span
              :if={is_nil(@memory.month) or is_nil(@memory.year)}
              class="text-[13px] text-ks-amber-deep"
            >
              Pick the month and year this was taken.
            </span>
            <span class="text-[13px] text-ks-muted">The timeline is ordered by month and year.</span>
          </fieldset>

          <div class="flex flex-col gap-1.5">
            <label for="memory-caption" class="text-sm font-bold">Caption</label>
            <.input
              field={@form[:caption]}
              id="memory-caption"
              type="textarea"
              rows="3"
              maxlength="280"
              placeholder="What was happening?"
              phx-debounce="300"
            />
            <span class="self-end text-[13px] tabular-nums text-ks-muted">
              {String.length(@form[:caption].value || "")} / 280
            </span>
          </div>

          <div class="flex flex-col gap-1.5">
            <label for="memory-place" class="text-sm font-bold">Location</label>
            <.input
              field={@form[:place]}
              id="memory-place"
              placeholder="Optional"
              maxlength="120"
              autocomplete="off"
              phx-debounce="300"
            />
          </div>

          <div class="flex flex-col gap-1.5">
            <label for="memory-people-input" class="text-sm font-bold">People in this photo</label>
            <div
              id="memory-people"
              class="flex flex-wrap items-center gap-2 rounded-field border border-ks-field p-2 focus-within:outline-2 focus-within:outline-offset-1 focus-within:outline-primary"
            >
              <span
                :for={{person, i} <- Enum.with_index(@memory.people)}
                class="flex items-center gap-1 rounded-full bg-base-200 py-1 pl-3 pr-1 text-sm"
              >
                {person}
                <button
                  type="button"
                  phx-click="remove_person"
                  phx-value-index={i}
                  aria-label={"Remove #{person}"}
                  class="flex size-[26px] cursor-pointer items-center justify-center rounded-full text-base-content/80 hover:bg-base-300"
                >
                  <.icon name="hero-x-mark" class="size-3" />
                </button>
              </span>
              <input
                id="memory-people-input"
                type="text"
                name="person"
                form="people-form"
                placeholder="Type a name, press Enter"
                autocomplete="off"
                maxlength="40"
                class="min-w-[140px] flex-1 border-0 bg-transparent p-1.5 text-[15px] outline-none"
              />
            </div>
          </div>

          <.input
            type="checkbox"
            name="memory[cover]"
            id="memory-cover"
            value={@cover}
            label="Use as album cover"
          />
        </.form>
        <%!-- Outside #memory-form: the people input submits this one on Enter --%>
        <form
          id="people-form"
          phx-submit={JS.push("add_person") |> JS.dispatch("ks:clear", to: "#memory-people-input")}
        >
        </form>
      </div>
    </section>
    """
  end

  defp month_options do
    Memory.month_names() |> Enum.with_index(1)
  end

  defp year_options do
    Date.utc_today().year..1900//-1 |> Enum.map(&{Integer.to_string(&1), &1})
  end
end
