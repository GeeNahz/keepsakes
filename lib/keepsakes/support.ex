defmodule Keepsakes.Support do
  @moduledoc """
  Help and support tickets.

  Owners open tickets from Help (`create_ticket/3`) and write back
  (`reply/4`); guests can report an album (`report_album/2`). Staff answer
  from the admin portal's inbox (`Keepsakes.Support.Admin`, which calls
  `staff_reply/4`). New tickets and customer replies are also emailed to
  the `SUPPORT_INBOX` address when one is set.

  Status follows who wrote last: the customer → `awaiting_staff`, support
  → `awaiting_user`. A `resolved` ticket reopens when the customer writes
  again, and closes after 7 quiet days (`close_resolved/1`, daily).

  Every change is broadcast on the ticket's topic so open pages update.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Keepsakes.Accounts.{Scope, User}
  alias Keepsakes.Sharing.ShareLink
  alias Keepsakes.Support.{Attachment, Message, Notifier, Ticket}
  alias Keepsakes.{Repo, Storage}

  @close_after_days 7

  ## Reading

  @doc "The owner's tickets, most recently active first."
  def list_tickets(%Scope{user: user}) do
    from(t in Ticket, where: t.user_id == ^user.id, order_by: [desc: t.last_activity_at])
    |> Repo.all()
  end

  @doc """
  The owner's ticket with `number`, with the messages they can see (staff
  notes left out) and their attachments. Raises when it isn't theirs.
  """
  def get_ticket!(%Scope{user: user}, number) do
    visible =
      from m in Message,
        where: not m.internal,
        order_by: [asc: m.inserted_at, asc: m.id],
        preload: [:attachments, :author]

    Repo.one!(
      from t in Ticket,
        where: t.user_id == ^user.id and t.number == ^number,
        preload: [messages: ^visible]
    )
  end

  def change_ticket(attrs \\ %{}), do: Ticket.changeset(%Ticket{}, attrs)

  @doc "A short-lived link to an attachment."
  def attachment_url(%Attachment{storage_key: key}), do: Storage.url(key)

  ## Customer actions

  @doc """
  Opens a ticket with its first message and `files`
  (`[%{path, filename, content_type, bytes}]`). Abuse reports start at
  high priority. Emails the owner a confirmation and the support inbox an
  alert.
  """
  @spec create_ticket(Scope.t(), map(), [map()]) ::
          {:ok, Ticket.t()} | {:error, Ecto.Changeset.t() | {:file, String.t(), atom()}}
  def create_ticket(%Scope{user: user}, attrs, files \\ []) do
    changeset = Ticket.changeset(%Ticket{}, attrs)

    with {:ok, data} <- Ecto.Changeset.apply_action(changeset, :insert),
         {:ok, files} <- prepare_files(files) do
      now = DateTime.utc_now(:second)

      Multi.new()
      |> Multi.insert(:ticket, %Ticket{
        number: next_number(),
        user_id: user.id,
        subject: data.subject,
        category: data.category,
        priority: if(data.category == "abuse", do: "high", else: "normal"),
        status: "open",
        last_activity_at: now
      })
      |> Multi.run(:message, fn _repo, %{ticket: ticket} ->
        insert_message(ticket, "user", user.id, data.body, files)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{ticket: ticket, message: message}} ->
          Notifier.deliver_ticket_received(user, ticket)
          Notifier.alert_staff(ticket, message, user.email)
          broadcast(ticket)
          {:ok, ticket}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  @doc """
  The owner writes on their ticket. Reopens a solved ticket; closed
  tickets take no more replies.
  """
  @spec reply(Scope.t(), Ticket.t(), String.t(), [map()]) ::
          {:ok, Message.t()} | {:error, :closed | :empty | {:file, String.t(), atom()}}
  def reply(
        %Scope{user: %{id: user_id} = user},
        %Ticket{user_id: user_id} = ticket,
        body,
        files \\ []
      ) do
    body = String.trim(body || "")

    cond do
      ticket.status == "closed" ->
        {:error, :closed}

      body == "" and files == [] ->
        {:error, :empty}

      true ->
        with {:ok, files} <- prepare_files(files) do
          save_reply(ticket, user, body, files)
        end
    end
  end

  defp save_reply(ticket, %User{id: user_id} = user, body, files) do
    result =
      Repo.transaction(fn ->
        {:ok, message} = insert_message(ticket, "user", user_id, body, files)

        ticket
        |> Ecto.Changeset.change(
          status: "awaiting_staff",
          resolved_at: nil,
          last_activity_at: DateTime.utc_now(:second)
        )
        |> Repo.update!()

        message
      end)

    with {:ok, message} <- result do
      Notifier.alert_staff(ticket, message, user.email)
      broadcast(ticket)
      {:ok, message}
    end
  end

  @doc "The owner marks their ticket solved."
  def resolve(%Scope{user: %{id: user_id}}, %Ticket{user_id: user_id, status: status} = ticket)
      when status not in ["resolved", "closed"] do
    set_status(ticket, "resolved", "Marked as solved", resolved_at: DateTime.utc_now(:second))
  end

  def resolve(_scope, _ticket), do: {:error, :not_open}

  @doc "The owner reopens a solved ticket."
  def reopen(
        %Scope{user: %{id: user_id}},
        %Ticket{user_id: user_id, status: "resolved"} = ticket
      ),
      do: set_status(ticket, "awaiting_staff", "Reopened", resolved_at: nil)

  def reopen(_scope, _ticket), do: {:error, :not_resolved}

  @doc "Rates a solved or closed ticket, 1 to 5, with an optional comment."
  def rate(
        %Scope{user: %{id: user_id}},
        %Ticket{user_id: user_id, status: status} = ticket,
        rating,
        comment
      )
      when status in ["resolved", "closed"] and rating in 1..5 do
    comment = comment |> to_string() |> String.trim() |> String.slice(0, 500)

    ticket
    |> Ecto.Changeset.change(
      rating: rating,
      rating_comment: if(comment == "", do: nil, else: comment),
      rated_at: DateTime.utc_now(:second)
    )
    |> Repo.update()
    |> tap(fn _ -> broadcast(ticket) end)
  end

  def rate(_scope, _ticket, _rating, _comment), do: {:error, :not_ratable}

  ## Guest reports

  @doc """
  A guest reports a shared album: an abuse ticket at high priority, linked
  to the album, with an optional email to reply to. `attrs`: `reason`,
  `details`, `email`.
  """
  @spec report_album(ShareLink.t(), map()) :: {:ok, Ticket.t()} | {:error, :invalid}
  def report_album(%ShareLink{} = link, attrs) do
    reason = attrs["reason"] |> to_string() |> String.trim()
    details = attrs["details"] |> to_string() |> String.trim() |> String.slice(0, 3000)
    email = attrs["email"] |> to_string() |> String.trim() |> String.slice(0, 160)
    email = if Regex.match?(~r/\A[^\s@]+@[^\s@]+\z/, email), do: email

    if reason in report_reasons() do
      now = DateTime.utc_now(:second)
      link = Repo.preload(link, :album)

      body =
        "Reason: #{reason}\nAlbum: #{link.album.name} (/a/#{link.slug})" <>
          if(details != "", do: "\n\n#{details}", else: "")

      Multi.new()
      |> Multi.insert(:ticket, %Ticket{
        number: next_number(),
        reporter_email: email,
        album_id: link.album_id,
        share_link_id: link.id,
        subject: "Album reported: #{reason}",
        category: "abuse",
        priority: "high",
        status: "open",
        last_activity_at: now
      })
      |> Multi.run(:message, fn _repo, %{ticket: ticket} ->
        insert_message(ticket, "guest", nil, body, [])
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{ticket: ticket, message: message}} ->
          Notifier.alert_staff(ticket, message, email)
          if email, do: Notifier.deliver_report_received(email, ticket)
          broadcast(ticket)
          {:ok, ticket}

        {:error, _, _, _} ->
          {:error, :invalid}
      end
    else
      {:error, :invalid}
    end
  end

  @doc "Reasons a guest can pick when reporting."
  def report_reasons do
    [
      "Shows me or my child without permission",
      "Nudity or sexual content",
      "Violence or abuse",
      "Copyright",
      "Spam or a scam",
      "Something else"
    ]
  end

  ## Staff (the admin inbox arrives in Stage 7)

  @doc """
  A staff reply (or, with `internal: true`, a note only staff see).
  Replies set `awaiting_user`, record the first response time and email
  the customer.
  """
  def staff_reply(%Ticket{} = ticket, %User{} = staff, body, opts \\ []) do
    internal = Keyword.get(opts, :internal, false)
    now = DateTime.utc_now(:second)

    {:ok, message} =
      Repo.transaction(fn ->
        {:ok, message} = insert_message(ticket, "staff", staff.id, body, [], internal)

        unless internal do
          ticket
          |> Ecto.Changeset.change(
            status: "awaiting_user",
            first_response_at: ticket.first_response_at || now,
            last_activity_at: now
          )
          |> Repo.update!()
        end

        message
      end)

    unless internal do
      ticket = Repo.preload(ticket, :user)
      if ticket.user, do: Notifier.deliver_staff_replied(ticket.user, ticket, message)
    end

    # Notes too, so other staff on the ticket see them
    broadcast(ticket)
    {:ok, message}
  end

  ## Housekeeping

  @doc "Closes tickets solved more than #{@close_after_days} days ago. Returns how many."
  def close_resolved(now \\ DateTime.utc_now(:second)) do
    cutoff = DateTime.add(now, -@close_after_days, :day)

    {count, tickets} =
      from(t in Ticket,
        where: t.status == "resolved" and t.resolved_at <= ^cutoff,
        select: t
      )
      |> Repo.update_all(set: [status: "closed", closed_at: now, updated_at: now])

    Enum.each(tickets, &broadcast/1)
    count
  end

  ## PubSub

  @doc "Subscribes to `{:ticket_updated, ticket_id}` for one ticket."
  def subscribe(%Ticket{id: id}), do: Phoenix.PubSub.subscribe(Keepsakes.PubSub, "ticket:#{id}")

  @doc "Subscribes to `{:ticket_updated, ticket_id}` for every ticket (the staff inbox)."
  def subscribe_inbox, do: Phoenix.PubSub.subscribe(Keepsakes.PubSub, "support:inbox")

  @doc "Tells open pages (the ticket's and the staff inbox) that it changed."
  def broadcast(%Ticket{id: id}) do
    Phoenix.PubSub.broadcast(Keepsakes.PubSub, "ticket:#{id}", {:ticket_updated, id})
    Phoenix.PubSub.broadcast(Keepsakes.PubSub, "support:inbox", {:ticket_updated, id})
  end

  ## Helpers

  @doc """
  Moves the ticket to `status` with `changes`, adding `note` to the thread
  as a system line (e.g. "Marked as solved"). Used by owners here and by
  staff through `Keepsakes.Support.Admin`.
  """
  def set_status(ticket, status, note, changes \\ []) do
    now = DateTime.utc_now(:second)

    result =
      Repo.transaction(fn ->
        {:ok, _} = insert_message(ticket, "system", nil, note, [])

        ticket
        |> Ecto.Changeset.change([status: status, last_activity_at: now] ++ changes)
        |> Repo.update!()
      end)

    with {:ok, ticket} <- result do
      broadcast(ticket)
      {:ok, ticket}
    end
  end

  # Stores the message and its files (under the ticket owner's prefix, so
  # deleting the account removes them too)
  defp insert_message(ticket, author_type, author_id, body, files, internal \\ false) do
    message =
      Repo.insert!(%Message{
        ticket_id: ticket.id,
        author_type: author_type,
        author_id: author_id,
        body: body,
        internal: internal
      })

    owner = ticket.user_id || "guests"

    Enum.each(files, fn file ->
      ext = if file.content_type == "image/webp", do: ".webp", else: ".pdf"
      key = "users/#{owner}/tickets/#{ticket.id}/#{Ecto.UUID.generate()}#{ext}"
      :ok = Storage.put(key, file.data, content_type: file.content_type)

      Repo.insert!(%Attachment{
        message_id: message.id,
        storage_key: key,
        filename: file.filename,
        content_type: file.content_type,
        bytes: byte_size(file.data)
      })
    end)

    {:ok, message}
  end

  @image_exts ~w(.jpg .jpeg .png .heic .heif .webp)
  @max_pdf_bytes 5_000_000
  @attachment_long_edge 1600

  @doc "Largest PDF attachment, in bytes (photos are shrunk instead)."
  def max_pdf_bytes, do: @max_pdf_bytes

  # Before anything is stored: photos become one small WebP (longest side
  # #{@attachment_long_edge} px, metadata stripped) so screenshots and phone
  # photos don't fill storage; PDFs must really be PDFs, at most 5 MB.
  defp prepare_files(files) do
    Enum.reduce_while(files, {:ok, []}, fn file, {:ok, acc} ->
      case prepare_file(file) do
        {:ok, prepared} -> {:cont, {:ok, acc ++ [prepared]}}
        {:error, reason} -> {:halt, {:error, {:file, file.filename, reason}}}
      end
    end)
  end

  defp prepare_file(%{path: path, filename: filename}) do
    ext = filename |> Path.extname() |> String.downcase()
    base = filename |> Path.basename() |> Path.rootname() |> String.slice(0, 150)

    cond do
      ext in @image_exts ->
        case Keepsakes.Media.shrink(path, @attachment_long_edge) do
          {:ok, data} ->
            {:ok, %{data: data, filename: base <> ".webp", content_type: "image/webp"}}

          {:error, _} ->
            {:error, :unreadable}
        end

      ext == ".pdf" ->
        %{size: size} = File.stat!(path)

        cond do
          size > @max_pdf_bytes ->
            {:error, :too_large}

          File.open!(path, [:read], &IO.binread(&1, 5)) != "%PDF-" ->
            {:error, :unreadable}

          true ->
            {:ok,
             %{data: File.read!(path), filename: base <> ".pdf", content_type: "application/pdf"}}
        end

      true ->
        {:error, :not_accepted}
    end
  end

  @doc "Friendly text for a file that couldn't be attached."
  def file_error(filename, :too_large), do: "#{filename} is over 5 MB. PDFs can be up to 5 MB."
  def file_error(filename, :unreadable), do: "#{filename} couldn't be read. Try another file."
  def file_error(filename, :not_accepted), do: "#{filename} isn't a photo or PDF."

  defp next_number do
    %{rows: [[n]]} = Repo.query!("SELECT nextval('ticket_number_seq')")
    "KS-T-#{n}"
  end
end
