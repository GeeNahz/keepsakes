defmodule KeepsakesWeb.SupportComponents do
  @moduledoc "Pieces of the Help pages: status badges, messages, attachments, the file picker."
  use KeepsakesWeb, :html

  alias Keepsakes.Support
  alias Keepsakes.Support.{Attachment, Ticket}

  @accept ~w(.jpg .jpeg .png .heic .heif .webp .pdf)

  @doc """
  Upload options for ticket attachments (`allow_upload(socket, :files, ...)`).
  Files start uploading as soon as they're picked, so progress shows
  straight away; photos are shrunk after upload, so 10 MB is only the
  limit on what's sent (PDFs are checked against 5 MB).
  """
  def upload_options,
    do: [accept: @accept, max_entries: 3, max_file_size: 10_000_000, auto_upload: true]

  @doc "Whether any picked file is still uploading (Send waits for them)."
  def uploading?(upload), do: Enum.any?(upload.entries, &(not &1.done?))

  @doc """
  Copies finished uploads somewhere they outlive the upload callback and
  returns them as files for `Keepsakes.Support`; `cleanup/1` removes them.
  """
  def take_files(socket, name) do
    Phoenix.LiveView.consume_uploaded_entries(socket, name, fn %{path: path}, entry ->
      copy = Path.join(System.tmp_dir!(), "ks-ticket-#{Ecto.UUID.generate()}")
      File.cp!(path, copy)

      {:ok,
       %{
         path: copy,
         filename: entry.client_name,
         content_type: entry.client_type || "application/octet-stream",
         bytes: entry.client_size
       }}
    end)
  end

  def cleanup(files), do: Enum.each(files, &File.rm(&1.path))

  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm whitespace-nowrap border-0",
      case @status do
        "awaiting_user" -> "bg-ks-amber-soft text-ks-amber-deep"
        s when s in ["resolved", "closed"] -> "bg-ks-teal-soft text-primary"
        _ -> "bg-base-300 text-base-content"
      end
    ]}>
      {Ticket.status_label(@status)}
    </span>
    """
  end

  attr :upload, :map, required: true

  @doc "Add-files button with the queue of chosen files."
  def file_picker(assigns) do
    ~H"""
    <div class="flex flex-col gap-2">
      <div class="flex flex-wrap items-center gap-3">
        <label
          for={@upload.ref}
          class="btn btn-ghost btn-sm min-h-9 cursor-pointer gap-1.5 rounded-field border border-ks-field bg-base-100 font-bold"
        >
          <.icon name="hero-paper-clip" class="size-4" /> Add photos or PDFs
        </label>
        <.live_file_input upload={@upload} class="sr-only" />
        <span class="text-[13px] text-ks-muted">
          Up to 3 · photos are resized to save space · PDFs up to 5 MB
        </span>
      </div>
      <ul :if={@upload.entries != []} class="flex flex-wrap gap-2">
        <li
          :for={entry <- @upload.entries}
          id={"file-#{entry.ref}"}
          class="flex min-w-48 flex-col gap-1 rounded-field bg-base-200 py-1.5 pl-3 pr-1 text-sm"
        >
          <div class="flex items-center gap-2">
            <span class="max-w-48 flex-1 truncate">{entry.client_name}</span>
            <span :for={err <- upload_errors(@upload, entry)} class="text-error">{error_text(err)}</span>
            <span :if={entry.valid? and not entry.done?} class="text-xs tabular-nums text-ks-muted">
              {entry.progress}%
            </span>
            <.icon :if={entry.done?} name="hero-check-circle" class="size-4 text-primary" />
            <button
              type="button"
              phx-click="cancel_file"
              phx-value-ref={entry.ref}
              aria-label={"Remove #{entry.client_name}"}
              class="flex size-7 cursor-pointer items-center justify-center rounded-full hover:bg-base-300"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>
          <progress
            :if={entry.valid? and not entry.done?}
            class="progress progress-primary h-1 w-full pr-2"
            value={entry.progress}
            max="100"
            aria-label={"Uploading #{entry.client_name}"}
          ></progress>
        </li>
      </ul>
      <p :for={err <- upload_errors(@upload)} class="text-sm text-error">{error_text(err)}</p>
    </div>
    """
  end

  defp error_text(:too_large), do: "over 10 MB"
  defp error_text(:not_accepted), do: "use photos or PDFs"
  defp error_text(:too_many_files), do: "Up to 3 files at a time."
  defp error_text(_), do: "couldn't be added"

  attr :message, :map, required: true

  @doc "One message in the conversation."
  def message_bubble(%{message: %{author_type: "system"}} = assigns) do
    ~H"""
    <li id={"message-#{@message.id}"} class="flex justify-center py-1">
      <span class="text-[13px] text-ks-muted">
        {@message.body} · {when_text(@message.inserted_at)}
      </span>
    </li>
    """
  end

  def message_bubble(assigns) do
    assigns = assign(assigns, :mine, assigns.message.author_type in ["user", "guest"])

    ~H"""
    <li id={"message-#{@message.id}"} class={["flex", @mine && "justify-end"]}>
      <div class={[
        "flex max-w-[85%] flex-col gap-2 rounded-2xl px-4 py-3",
        if(@mine, do: "bg-ks-teal-soft", else: "border border-base-300 bg-base-100")
      ]}>
        <div class="flex items-center gap-2 text-[13px] text-ks-muted">
          <span class="font-bold text-base-content">
            {if @mine, do: "You", else: "Keepsake support"}
          </span>
          <span>{when_text(@message.inserted_at)}</span>
        </div>
        <p :if={@message.body != ""} class="whitespace-pre-line text-[15px] leading-relaxed">
          {@message.body}
        </p>
        <div :if={@message.attachments != []} class="flex flex-wrap gap-2">
          <.attachment :for={attachment <- @message.attachments} attachment={attachment} />
        </div>
      </div>
    </li>
    """
  end

  attr :attachment, Attachment, required: true

  @doc "A link to an attachment (a thumbnail for photos)."
  def attachment(assigns) do
    ~H"""
    <a
      href={Support.attachment_url(@attachment)}
      target="_blank"
      rel="noopener"
      class="flex items-center gap-2 rounded-field border border-base-300 bg-base-100 p-1.5 pr-3 text-sm no-underline"
    >
      <img
        :if={Attachment.image?(@attachment)}
        src={Support.attachment_url(@attachment)}
        alt=""
        class="size-10 rounded object-cover"
      />
      <.icon :if={!Attachment.image?(@attachment)} name="hero-document" class="size-6 text-ks-muted" />
      <span class="max-w-40 truncate">{@attachment.filename}</span>
    </a>
    """
  end

  @doc "`\"26 Oct, 14:05\"` (UTC)."
  def when_text(at), do: Calendar.strftime(at, "%-d %b, %H:%M")
end
