defmodule KeepsakesWeb.SupportLive.Index do
  @moduledoc """
  `/app/help`: contact support (category, subject, message, up to three
  photos or PDFs) and the owner's tickets.
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
          <h1 class="text-[32px] font-bold">Help &amp; support</h1>
          <p class="text-base text-ks-muted">
            Tell us what's going on and we'll get back to you by email and here.
          </p>
        </div>

        <section
          id="new-ticket"
          aria-label="Contact support"
          class="flex flex-col gap-4 rounded-2xl border border-base-300 bg-base-100 p-6"
        >
          <h2 class="text-lg font-bold">Contact support</h2>
          <.form
            for={@form}
            id="ticket-form"
            phx-change="validate"
            phx-submit="create"
            class="flex flex-col gap-1"
          >
            <div class="grid gap-x-3 sm:grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)]">
              <.input
                field={@form[:category]}
                type="select"
                label="What's it about?"
                prompt="Choose one"
                options={Ticket.category_options()}
              />
              <.input field={@form[:subject]} label="Subject" maxlength="120" />
            </div>
            <.input
              field={@form[:body]}
              type="textarea"
              label="Message"
              rows="5"
              maxlength="5000"
              placeholder="What happened, and what did you expect? Album names and links help."
            />
            <.file_picker upload={@uploads.files} />
            <div class="pt-3">
              <.button
                id="send-ticket"
                variant="primary"
                phx-disable-with="Sending…"
                disabled={uploading?(@uploads.files)}
              >
                {if uploading?(@uploads.files), do: "Uploading…", else: "Send to support"}
              </.button>
            </div>
          </.form>
        </section>

        <section id="tickets" aria-label="Your tickets" class="flex flex-col gap-3">
          <h2 class="text-lg font-bold">Your tickets</h2>
          <p :if={@tickets == []} id="no-tickets" class="text-sm text-ks-muted">
            No tickets yet.
          </p>
          <ul
            :if={@tickets != []}
            class="flex flex-col divide-y divide-base-300 overflow-hidden rounded-2xl border border-base-300 bg-base-100"
          >
            <li :for={ticket <- @tickets} id={"ticket-#{ticket.number}"}>
              <.link
                navigate={~p"/app/help/#{ticket.number}"}
                class="flex flex-wrap items-center justify-between gap-3 px-5 py-4 text-base-content no-underline transition-colors hover:bg-base-200"
              >
                <div class="flex min-w-0 flex-col gap-0.5">
                  <span class="truncate font-medium">{ticket.subject}</span>
                  <span class="font-mono text-[13px] text-ks-muted">
                    {ticket.number} · {when_text(ticket.last_activity_at)}
                  </span>
                </div>
                <.status_badge status={ticket.status} />
              </.link>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Help & support",
       form: to_form(Support.change_ticket(), as: :ticket),
       tickets: Support.list_tickets(socket.assigns.current_scope)
     )
     |> allow_upload(:files, upload_options())}
  end

  @impl true
  def handle_event("validate", %{"ticket" => params}, socket) do
    changeset = params |> Support.change_ticket() |> Map.put(:action, :validate)
    {:noreply, assign(socket, form: to_form(changeset, as: :ticket))}
  end

  def handle_event("cancel_file", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :files, ref)}

  def handle_event("create", %{"ticket" => params}, socket) do
    if Support.change_ticket(params).valid? do
      files = take_files(socket, :files)
      result = Support.create_ticket(socket.assigns.current_scope, params, files)
      cleanup(files)

      case result do
        {:ok, ticket} ->
          {:noreply,
           socket
           |> put_flash(:info, "Thanks, we've got it. We'll reply by email and here.")
           |> push_navigate(to: ~p"/app/help/#{ticket.number}")}

        {:error, {:file, filename, reason}} ->
          {:noreply, put_flash(socket, :error, Support.file_error(filename, reason))}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(changeset, as: :ticket))}
      end
    else
      changeset = params |> Support.change_ticket() |> Map.put(:action, :insert)
      {:noreply, assign(socket, form: to_form(changeset, as: :ticket))}
    end
  end
end
