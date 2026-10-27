defmodule KeepsakesWeb.Admin.SupportLive.Show do
  @moduledoc """
  `admin.<host>/support/:number`: one ticket's whole thread (internal notes
  highlighted), who it's from, the reported album, and the reply box with
  an internal-note switch and canned replies. Assignee and priority need
  `support.assign`; replying and status need `support.reply`. The thread
  updates live. Needs `support.view`.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.SupportComponents, only: [attachment: 1, when_text: 1]
  import KeepsakesWeb.Admin.SupportLive.Index, only: [sla_badge: 1, staff_status_badge: 1]

  alias Keepsakes.Accounts.User
  alias Keepsakes.Support
  alias Keepsakes.Support.Admin
  alias Keepsakes.Staff.Scope, as: StaffScope

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:support}>
      <.link navigate={~p"/support"} class="mb-4 flex w-fit items-center gap-1 text-sm text-ks-muted">
        <.icon name="hero-arrow-left" class="size-4" /> Support
      </.link>

      <header class="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div class="flex flex-col gap-1.5">
          <span class="font-mono text-sm text-ks-muted">{@ticket.number}</span>
          <h1 class="font-display text-3xl font-bold">{@ticket.subject}</h1>
          <div class="flex flex-wrap items-center gap-2">
            <.staff_status_badge status={@ticket.status} />
            <.sla_badge ticket={@ticket} />
          </div>
        </div>
        <div :if={@can_reply?} id="ticket-actions" class="flex flex-wrap gap-2">
          <.button
            :if={@ticket.status not in ["resolved", "closed"]}
            id="mark-solved"
            size="sm"
            phx-click="status"
            phx-value-to="resolved"
          >
            Mark solved
          </.button>
          <.button
            :if={@ticket.status in ["resolved", "closed"]}
            id="reopen"
            size="sm"
            phx-click="status"
            phx-value-to="awaiting_staff"
          >
            Reopen
          </.button>
          <.button
            :if={@ticket.status != "closed"}
            id="close-ticket"
            size="sm"
            phx-click="status"
            phx-value-to="closed"
          >
            Close
          </.button>
        </div>
      </header>

      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_300px]">
        <section class="flex min-w-0 flex-col gap-4">
          <ol id="thread" class="flex flex-col gap-3">
            <.staff_bubble :for={m <- @ticket.messages} message={m} />
          </ol>

          <.form
            :if={@can_reply?}
            for={@reply_form}
            id="reply-form"
            phx-change="draft"
            phx-submit="send"
            class={[
              "flex flex-col gap-3 rounded-box border bg-base-100 p-4",
              if(@internal?, do: "border-ks-amber-soft", else: "border-base-300")
            ]}
          >
            <div class="flex flex-wrap items-center justify-between gap-3">
              <label class="flex cursor-pointer items-center gap-2 text-sm font-medium">
                <input type="hidden" name="reply[internal]" value="false" />
                <input
                  type="checkbox"
                  id="reply-internal"
                  name="reply[internal]"
                  value="true"
                  checked={@internal?}
                  class="toggle toggle-sm toggle-warning"
                /> Internal note (only staff see it)
              </label>
              <select
                :if={@replies != []}
                id="canned-picker"
                name="reply[canned]"
                class="select select-sm w-56 border-ks-field bg-base-100"
              >
                <option value="">Insert a canned reply…</option>
                <option :for={r <- @replies} value={r.id}>{r.title}</option>
              </select>
            </div>
            <.input
              field={@reply_form[:body]}
              type="textarea"
              rows="5"
              placeholder={if(@internal?, do: "A note for the team…", else: "Write to the customer…")}
              phx-debounce="300"
            />
            <p :if={@reply_error} id="reply-error" class="text-sm text-error">{@reply_error}</p>
            <div class="flex justify-end">
              <.button
                id="send-reply"
                variant={if(@internal?, do: "secondary", else: "primary")}
                phx-disable-with="Sending…"
              >
                {if @internal?, do: "Add note", else: "Send reply"}
              </.button>
            </div>
          </.form>
        </section>

        <aside class="flex flex-col gap-4">
          <section
            id="ticket-customer"
            class="flex flex-col gap-2 rounded-box border border-base-300 bg-base-100 p-4 text-[15px]"
          >
            <h2 class="text-sm font-bold uppercase tracking-[0.06em] text-ks-muted">From</h2>
            <%= if @ticket.user do %>
              <p class="font-bold">{User.full_name(@ticket.user)}</p>
              <p class="break-all text-sm text-ks-muted">{@ticket.user.email}</p>
              <.link
                :if={@customers? and not Keepsakes.Staff.staff?(@ticket.user)}
                id="open-customer"
                navigate={~p"/customers/#{@ticket.user_id}"}
                class="w-fit text-sm font-bold text-primary"
              >
                Open customer
              </.link>
            <% else %>
              <p>A guest</p>
              <p class="break-all text-sm text-ks-muted">
                {@ticket.reporter_email || "No email left"}
              </p>
            <% end %>
            <p :if={@ticket.album} id="reported-album" class="text-sm">
              Album: <span class="font-medium">{@ticket.album.name}</span>
              <span :if={@ticket.share_link} class="block font-mono text-xs text-ks-muted">
                /a/{@ticket.share_link.slug}
              </span>
            </p>
            <p :if={@ticket.rating} id="ticket-rating" class="text-sm">
              Rated {@ticket.rating}/5{if @ticket.rating_comment, do: ": “#{@ticket.rating_comment}”"}
            </p>
          </section>

          <section
            id="ticket-details"
            class="flex flex-col gap-3 rounded-box border border-base-300 bg-base-100 p-4"
          >
            <h2 class="text-sm font-bold uppercase tracking-[0.06em] text-ks-muted">Details</h2>
            <%= if @can_assign? do %>
              <.form for={%{}} id="assign-form" phx-change="assign">
                <label for="assignee" class="mb-1 block text-sm font-medium">Assigned to</label>
                <select
                  id="assignee"
                  name="assignee_id"
                  class="select select-sm w-full border-ks-field bg-base-100"
                >
                  <option value="">Nobody</option>
                  <option :for={s <- @staff} value={s.id} selected={s.id == @ticket.assignee_id}>
                    {User.full_name(s)}
                  </option>
                </select>
              </.form>
              <.form for={%{}} id="priority-form" phx-change="priority">
                <label for="priority" class="mb-1 block text-sm font-medium">Priority</label>
                <select
                  id="priority"
                  name="priority"
                  class="select select-sm w-full border-ks-field bg-base-100"
                >
                  <option :for={p <- Admin.priorities()} value={p} selected={p == @ticket.priority}>
                    {String.capitalize(p)} · first reply within {Admin.sla_hours(p)}h
                  </option>
                </select>
              </.form>
            <% else %>
              <p class="text-sm">
                Assigned to {(@ticket.assignee && User.full_name(@ticket.assignee)) || "nobody"}
              </p>
              <p class="text-sm">Priority: {String.capitalize(@ticket.priority)}</p>
            <% end %>
            <p class="text-xs text-ks-muted">
              Opened {when_text(@ticket.inserted_at)} UTC · first reply due {when_text(
                Admin.due_at(@ticket)
              )}
            </p>
          </section>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  attr :message, :map, required: true

  # Staff's view: customers on the left, staff on the right, notes in amber
  defp staff_bubble(%{message: %{author_type: "system"}} = assigns) do
    ~H"""
    <li id={"message-#{@message.id}"} class="flex justify-center py-1">
      <span class="text-[13px] text-ks-muted">{@message.body} · {when_text(@message.inserted_at)}</span>
    </li>
    """
  end

  defp staff_bubble(assigns) do
    assigns = assign(assigns, :staff, assigns.message.author_type == "staff")

    ~H"""
    <li id={"message-#{@message.id}"} class={["flex", @staff && "justify-end"]}>
      <div class={[
        "flex max-w-[85%] flex-col gap-2 rounded-2xl px-4 py-3",
        cond do
          @message.internal -> "border border-dashed border-ks-amber-deep/40 bg-ks-amber-soft"
          @staff -> "bg-ks-teal-soft"
          true -> "border border-base-300 bg-base-100"
        end
      ]}>
        <div class="flex flex-wrap items-center gap-2 text-[13px] text-ks-muted">
          <span class="font-bold text-base-content">{author(@message)}</span>
          <span :if={@message.internal} class="font-bold text-ks-amber-deep">Internal note</span>
          <span>{when_text(@message.inserted_at)}</span>
        </div>
        <p :if={@message.body != ""} class="whitespace-pre-line text-[15px] leading-relaxed">
          {@message.body}
        </p>
        <div :if={@message.attachments != []} class="flex flex-wrap gap-2">
          <.attachment :for={a <- @message.attachments} attachment={a} />
        </div>
      </div>
    </li>
    """
  end

  defp author(%{author_type: "guest"}), do: "Guest"
  defp author(%{author: %User{} = user}), do: User.full_name(user)
  defp author(%{author_type: "staff"}), do: "Support"
  defp author(_message), do: "Customer"

  @impl true
  def mount(%{"number" => number}, _session, socket) do
    scope = socket.assigns.staff_scope
    ticket = Admin.get!(scope, number)
    if connected?(socket), do: Support.subscribe(ticket)

    {:ok,
     socket
     |> assign(
       page_title: ticket.number,
       can_reply?: StaffScope.can?(scope, "support.reply"),
       can_assign?: StaffScope.can?(scope, "support.assign"),
       customers?: StaffScope.can?(scope, "users.view"),
       staff: Admin.assignable_staff(),
       replies: Admin.list_replies(scope),
       internal?: false,
       reply_error: nil,
       reply_form: to_form(%{"body" => ""}, as: :reply)
     )
     |> assign(:ticket, ticket)}
  end

  @impl true
  def handle_event("draft", %{"_target" => ["reply", "canned"], "reply" => params}, socket) do
    # Picking a canned reply adds its text to what's typed so far
    body =
      case Enum.find(socket.assigns.replies, &(&1.id == params["canned"])) do
        nil -> params["body"]
        reply -> String.trim(Enum.join([params["body"], reply.body], "\n\n"))
      end

    {:noreply, assign(socket, reply_form: to_form(%{"body" => body}, as: :reply))}
  end

  def handle_event("draft", %{"reply" => params}, socket) do
    {:noreply,
     assign(socket,
       internal?: params["internal"] == "true",
       reply_form: to_form(%{"body" => params["body"]}, as: :reply)
     )}
  end

  def handle_event("send", %{"reply" => params}, socket) do
    internal? = params["internal"] == "true"

    case Admin.reply(socket.assigns.staff_scope, socket.assigns.ticket, params["body"], internal?) do
      {:ok, _message} ->
        {:noreply,
         socket
         |> reload()
         |> assign(reply_error: nil, reply_form: to_form(%{"body" => ""}, as: :reply))
         |> put_flash(:info, if(internal?, do: "Note added.", else: "Reply sent."))}

      {:error, :empty} ->
        {:noreply, assign(socket, reply_error: "Write something first.")}

      {:error, :closed} ->
        {:noreply, assign(socket, reply_error: "This ticket is closed. Reopen it to reply.")}
    end
  end

  def handle_event("status", %{"to" => status}, socket) do
    case Admin.set_status(socket.assigns.staff_scope, socket.assigns.ticket, status) do
      {:ok, _} ->
        {:noreply, reload(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "That can't be done to this ticket now.")}
    end
  end

  def handle_event("assign", %{"assignee_id" => id}, socket) do
    case Admin.assign(socket.assigns.staff_scope, socket.assigns.ticket, id) do
      {:ok, _} ->
        {:noreply, socket |> reload() |> put_flash(:info, "Assignment saved.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "They can't be assigned support tickets.")}
    end
  end

  def handle_event("priority", %{"priority" => priority}, socket) do
    {:ok, _} = Admin.set_priority(socket.assigns.staff_scope, socket.assigns.ticket, priority)
    {:noreply, socket |> reload() |> put_flash(:info, "Priority saved.")}
  end

  @impl true
  def handle_info({:ticket_updated, _id}, socket), do: {:noreply, reload(socket)}
  # Anything else (e.g. the test mail adapter's copies of sent emails)
  def handle_info(_message, socket), do: {:noreply, socket}

  defp reload(socket),
    do:
      assign(
        socket,
        :ticket,
        Admin.get!(socket.assigns.staff_scope, socket.assigns.ticket.number)
      )
end
