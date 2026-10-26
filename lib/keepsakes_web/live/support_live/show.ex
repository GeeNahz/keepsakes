defmodule KeepsakesWeb.SupportLive.Show do
  @moduledoc """
  `/app/help/:number`: one ticket's conversation, updating live when
  support replies. Reply with text and files, mark it solved or reopen it,
  and rate it once solved.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.SupportComponents

  alias Keepsakes.Support
  alias Keepsakes.Support.Ticket

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} owner={@owner}>
      <div class="mx-auto flex w-full max-w-[880px] flex-col gap-6">
        <div class="flex flex-col gap-1.5">
          <.link
            id="ticket-back"
            navigate={~p"/app/help"}
            class="w-fit text-sm font-medium no-underline"
          >
            ← Help &amp; support
          </.link>
          <div class="flex flex-wrap items-center gap-3">
            <h1 id="ticket-subject" class="text-[28px] font-bold leading-tight">{@ticket.subject}</h1>
            <.status_badge status={@ticket.status} />
          </div>
          <p class="font-mono text-sm text-ks-muted">{@ticket.number}</p>
        </div>

        <ul id="ticket-messages" class="flex flex-col gap-3">
          <.message_bubble :for={message <- @ticket.messages} message={message} />
        </ul>

        <section
          :if={@ticket.status in ["resolved", "closed"]}
          id="ticket-rating"
          class="flex flex-col gap-3 rounded-2xl border border-base-300 bg-base-100 p-5"
        >
          <%= if @ticket.rating do %>
            <p class="text-[15px]">
              Thanks for your feedback: {@ticket.rating} out of 5.
            </p>
          <% else %>
            <h2 class="font-bold">How did we do?</h2>
            <form id="rating-form" phx-submit="rate" class="flex flex-col gap-3">
              <div class="flex gap-1.5" role="radiogroup" aria-label="Rating">
                <label
                  :for={n <- 1..5}
                  class="has-checked:bg-primary has-checked:text-primary-content flex size-11 cursor-pointer items-center justify-center rounded-full border border-ks-field font-bold"
                >
                  <input type="radio" name="rating" value={n} class="sr-only" required /> {n}
                </label>
              </div>
              <input
                id="rating-comment"
                name="comment"
                type="text"
                maxlength="500"
                placeholder="Anything we could do better? (optional)"
                class="input h-11 border-ks-field bg-base-100"
              />
              <.button variant="primary" size="sm" class="self-start">Send feedback</.button>
            </form>
          <% end %>
        </section>

        <section
          :if={Ticket.open?(@ticket)}
          id="ticket-reply"
          class="flex flex-col gap-3 rounded-2xl border border-base-300 bg-base-100 p-5"
        >
          <form
            id="reply-form"
            phx-change="validate_reply"
            phx-submit="reply"
            class="flex flex-col gap-3"
          >
            <textarea
              id="reply-body"
              name="body"
              rows="4"
              maxlength="5000"
              placeholder={
                if @ticket.status == "resolved",
                  do: "Still need help? Writing here reopens the ticket.",
                  else: "Write a reply…"
              }
              class="textarea w-full border-ks-field bg-base-100 text-[15px]"
            >{@reply}</textarea>
            <.file_picker upload={@uploads.files} />
            <div class="flex flex-wrap items-center justify-between gap-3">
              <.button
                id="send-reply"
                variant="primary"
                phx-disable-with="Sending…"
                disabled={uploading?(@uploads.files)}
              >
                {if uploading?(@uploads.files), do: "Uploading…", else: "Send"}
              </.button>
              <.button
                :if={@ticket.status != "resolved"}
                id="resolve-ticket"
                type="button"
                size="sm"
                phx-click="resolve"
              >
                <.icon name="hero-check" class="size-4" /> Mark as solved
              </.button>
              <.button
                :if={@ticket.status == "resolved"}
                id="reopen-ticket"
                type="button"
                size="sm"
                phx-click="reopen"
              >
                Reopen
              </.button>
            </div>
          </form>
        </section>

        <p :if={@ticket.status == "closed"} id="ticket-closed" class="text-sm text-ks-muted">
          This ticket is closed. Need more help? <.link navigate={~p"/app/help"} class="font-bold">Open a new one</.link>.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"number" => number}, _session, socket) do
    ticket = Support.get_ticket!(socket.assigns.current_scope, number)
    if connected?(socket), do: Support.subscribe(ticket)

    {:ok,
     socket
     |> assign(page_title: ticket.subject, ticket: ticket, reply: "")
     |> allow_upload(:files, upload_options())}
  end

  @impl true
  def handle_event("validate_reply", %{"body" => body}, socket),
    do: {:noreply, assign(socket, reply: body)}

  def handle_event("cancel_file", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :files, ref)}

  def handle_event("reply", %{"body" => body}, socket) do
    %{current_scope: scope, ticket: ticket} = socket.assigns
    files = take_files(socket, :files)
    result = Support.reply(scope, ticket, body, files)
    cleanup(files)

    case result do
      {:ok, _message} ->
        {:noreply, socket |> assign(reply: "") |> reload()}

      {:error, {:file, filename, reason}} ->
        {:noreply, put_flash(socket, :error, Support.file_error(filename, reason))}

      {:error, :empty} ->
        {:noreply, put_flash(socket, :error, "Write a message or add a file.")}

      {:error, :closed} ->
        {:noreply, socket |> reload() |> put_flash(:error, "This ticket is closed.")}
    end
  end

  def handle_event("resolve", _params, socket) do
    {:ok, _} = Support.resolve(socket.assigns.current_scope, socket.assigns.ticket)

    {:noreply,
     socket |> reload() |> put_flash(:info, "Glad it's sorted. You can reopen it if needed.")}
  end

  def handle_event("reopen", _params, socket) do
    {:ok, _} = Support.reopen(socket.assigns.current_scope, socket.assigns.ticket)
    {:noreply, reload(socket)}
  end

  def handle_event("rate", %{"rating" => rating} = params, socket) do
    case Integer.parse(rating) do
      {n, ""} ->
        Support.rate(socket.assigns.current_scope, socket.assigns.ticket, n, params["comment"])
        {:noreply, socket |> reload() |> put_flash(:info, "Thanks for the feedback.")}

      _ ->
        {:noreply, socket}
    end
  end

  # Support replied, or the ticket changed elsewhere
  @impl true
  def handle_info({:ticket_updated, _id}, socket), do: {:noreply, reload(socket)}

  defp reload(socket) do
    ticket = Support.get_ticket!(socket.assigns.current_scope, socket.assigns.ticket.number)
    assign(socket, ticket: ticket)
  end
end
