defmodule KeepsakesWeb.Admin.SupportLive.Replies do
  @moduledoc """
  `admin.<host>/support/replies`: canned replies, saved answers staff can
  insert into a reply and edit before sending. Anyone with `support.reply`
  can add, change or delete them. Needs `support.view`.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Staff.Scope, as: StaffScope
  alias Keepsakes.Support.{Admin, CannedReply}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:support}>
      <.link navigate={~p"/support"} class="mb-4 flex w-fit items-center gap-1 text-sm text-ks-muted">
        <.icon name="hero-arrow-left" class="size-4" /> Support
      </.link>
      <.header>
        Canned replies
        <:subtitle>
          Saved answers to insert into a reply. They can be edited before sending.
        </:subtitle>
        <:actions :if={@can_edit?}>
          <.button id="new-reply" variant="primary" phx-click="edit" phx-value-id="new">
            <.icon name="hero-plus" class="size-4" /> New reply
          </.button>
        </:actions>
      </.header>

      <div id="replies" phx-update="stream" class="flex flex-col gap-3">
        <p id="replies-empty" class="hidden text-ks-muted only:block">No canned replies yet.</p>
        <article
          :for={{id, reply} <- @streams.replies}
          id={id}
          class="flex flex-col gap-2 rounded-box border border-base-300 bg-base-100 p-4"
        >
          <div class="flex items-start justify-between gap-3">
            <h2 class="font-bold">{reply.title}</h2>
            <div :if={@can_edit?} class="flex shrink-0 gap-2">
              <.button
                id={"edit-reply-#{reply.id}"}
                size="sm"
                phx-click="edit"
                phx-value-id={reply.id}
              >
                Edit
              </.button>
              <.button
                :if={@confirm_delete != reply.id}
                id={"delete-reply-#{reply.id}"}
                size="sm"
                phx-click="ask_delete"
                phx-value-id={reply.id}
              >
                Delete
              </.button>
              <.button
                :if={@confirm_delete == reply.id}
                id={"confirm-delete-reply-#{reply.id}"}
                size="sm"
                variant="danger"
                phx-click="delete"
                phx-value-id={reply.id}
              >
                Confirm delete
              </.button>
            </div>
          </div>
          <p class="whitespace-pre-line text-sm text-ks-muted">{reply.body}</p>
        </article>
      </div>

      <.modal
        :if={@form}
        id="reply-dialog"
        show
        title={if(@editing.id, do: "Edit canned reply", else: "New canned reply")}
        box_class="max-w-[640px]"
        on_cancel={JS.push("close")}
      >
        <.form for={@form} id="canned-reply-form" phx-submit="save" class="flex flex-col gap-2">
          <.input field={@form[:title]} label="Title (only staff see it)" maxlength="80" required />
          <.input field={@form[:body]} type="textarea" label="Reply" rows="8" required />
          <div class="flex justify-end gap-2.5 pt-1">
            <.button type="button" phx-click={JS.exec("data-cancel", to: "#reply-dialog")}>Cancel</.button>
            <.button id="save-reply" variant="primary" phx-disable-with="Saving…">Save</.button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.staff_scope

    {:ok,
     socket
     |> assign(
       page_title: "Canned replies",
       can_edit?: StaffScope.can?(scope, "support.reply"),
       form: nil,
       editing: nil,
       confirm_delete: nil
     )
     |> stream(:replies, Admin.list_replies(scope))}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    reply =
      if id == "new", do: %CannedReply{}, else: Admin.get_reply!(socket.assigns.staff_scope, id)

    {:noreply, assign(socket, editing: reply, form: to_form(Admin.change_reply(reply)))}
  end

  def handle_event("close", _params, socket),
    do: {:noreply, assign(socket, form: nil, editing: nil)}

  def handle_event("save", %{"canned_reply" => params}, socket) do
    case Admin.save_reply(socket.assigns.staff_scope, socket.assigns.editing, params) do
      {:ok, reply} ->
        {:noreply,
         socket
         |> assign(form: nil, editing: nil)
         |> stream_insert(:replies, reply)
         |> put_flash(:info, "Saved #{reply.title}.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("ask_delete", %{"id" => id}, socket) do
    reply = Admin.get_reply!(socket.assigns.staff_scope, id)
    {:noreply, socket |> assign(confirm_delete: id) |> stream_insert(:replies, reply)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.staff_scope
    {:ok, reply} = Admin.delete_reply(scope, Admin.get_reply!(scope, id))
    {:noreply, socket |> assign(confirm_delete: nil) |> stream_delete(:replies, reply)}
  end
end
