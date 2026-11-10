defmodule KeepsakesWeb.AlbumLive.People do
  @moduledoc """
  `/app/albums/:slug/people`: the owner's collaborators on an album.

  Invite someone by email as an editor (adds and edits photos, reviews
  guest photos and notes) or a viewer (sees every photo). Seats on the
  plan count distinct people across all the owner's albums. Pending
  invitations can be resent or cancelled; members can change role or be
  removed. Owner only (`Keepsakes.Albums.Members`).
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.{Albums, Entitlements}
  alias Keepsakes.Albums.{Member, Members}
  alias KeepsakesWeb.OwnerShell

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} owner={@owner}>
      <div class="mx-auto flex w-full max-w-[860px] flex-col gap-6">
        <div class="flex flex-col gap-1.5">
          <.link
            id="people-back"
            navigate={~p"/app/albums/#{@album.slug}"}
            class="w-fit text-sm font-medium no-underline"
          >
            ← {@album.name}
          </.link>
          <h1 class="text-[32px] font-bold">People</h1>
          <p class="text-base text-ks-muted">
            Invite family or friends to help build this album. Editors add and edit photos; viewers see every photo. Only you can share it, change its code or delete it.
          </p>
        </div>

        <section
          id="people-invite"
          class="flex flex-col gap-4 rounded-2xl border border-base-300 bg-base-100 p-6"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="text-lg font-bold">Invite someone</h2>
            <span id="people-seats" class="text-sm text-ks-muted">{seats_text(
              @seats_used,
              @seat_limit
            )}</span>
          </div>

          <%= if @seat_limit == 0 do %>
            <div id="people-upgrade" class="flex flex-wrap items-center justify-between gap-3">
              <p class="text-[15px] text-ks-muted">Collaborators aren't included in your plan.</p>
              <.button id="people-see-plans" size="sm" navigate={~p"/app/settings/billing"}>
                See plans
              </.button>
            </div>
          <% else %>
            <.form
              for={@form}
              id="invite-form"
              phx-change="validate"
              phx-submit="invite"
              class="grid items-start gap-3 sm:grid-cols-[minmax(0,1fr)_160px_auto]"
            >
              <.input field={@form[:email]} type="email" placeholder="name@example.com" required />
              <.input
                field={@form[:role]}
                type="select"
                options={[{"Editor", "editor"}, {"Viewer", "viewer"}]}
              />
              <.button id="invite-submit" variant="primary" phx-disable-with="Sending…">
                Send invitation
              </.button>
            </.form>
            <p :if={@limit_error} id="invite-limit" class="text-sm text-error">{@limit_error}</p>
          <% end %>
        </section>

        <section id="people-list" class="flex flex-col gap-3">
          <h2 class="text-lg font-bold">On this album</h2>
          <p :if={@members == []} id="people-empty" class="text-ks-muted">
            Just you so far.
          </p>
          <article
            :for={member <- @members}
            id={"member-#{member.id}"}
            class="flex flex-wrap items-center justify-between gap-3 rounded-box border border-base-300 bg-base-100 px-5 py-4"
          >
            <div class="flex min-w-0 flex-col gap-0.5">
              <span class="truncate font-bold">
                {if member.user,
                  do: Keepsakes.Accounts.User.full_name(member.user),
                  else: member.email}
              </span>
              <span class="text-sm text-ks-muted">
                {member.email} · {if Member.accepted?(member), do: "joined", else: "invitation sent"}
              </span>
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <form id={"member-role-#{member.id}"} phx-change="change_role">
                <input type="hidden" name="member_id" value={member.id} />
                <select name="role" class="select select-sm" aria-label="Role">
                  <option value="editor" selected={member.role == "editor"}>Editor</option>
                  <option value="viewer" selected={member.role == "viewer"}>Viewer</option>
                </select>
              </form>
              <.button
                :if={not Member.accepted?(member)}
                id={"member-resend-#{member.id}"}
                size="sm"
                phx-click="resend"
                phx-value-id={member.id}
              >
                Resend
              </.button>
              <.button
                id={"member-remove-#{member.id}"}
                size="sm"
                variant="danger"
                phx-click="remove"
                phx-value-id={member.id}
                data-confirm={
                  if Member.accepted?(member),
                    do: "Remove #{member.email} from this album?",
                    else: "Cancel the invitation to #{member.email}?"
                }
              >
                {if Member.accepted?(member), do: "Remove", else: "Cancel"}
              </.button>
            </div>
          </article>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope
    album = Albums.get_album_by_slug!(scope, slug)

    {:ok,
     socket
     |> OwnerShell.put_current_album(album.id)
     |> assign(page_title: "People · #{album.name}", album: album, limit_error: nil)
     |> assign(form: to_form(Members.change_invite()))
     |> load()}
  end

  @impl true
  def handle_event("validate", %{"member" => params}, socket) do
    form = params |> Members.change_invite() |> Map.put(:action, :validate) |> to_form()
    {:noreply, assign(socket, form: form, limit_error: nil)}
  end

  def handle_event("invite", %{"member" => params}, socket) do
    %{current_scope: scope, album: album} = socket.assigns

    case Members.invite(scope, album, params) do
      {:ok, member} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent to #{member.email}.")
         |> assign(
           form: to_form(Members.change_invite(%{"role" => member.role})),
           limit_error: nil
         )
         |> load()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, {:over_limit, _, _, _} = over} ->
        {:noreply, assign(socket, limit_error: seat_message(over))}
    end
  end

  def handle_event("change_role", %{"member_id" => id, "role" => role}, socket) do
    %{current_scope: scope, album: album} = socket.assigns

    case Members.change_role(scope, album, member!(socket, id), role) do
      {:ok, member} ->
        {:noreply,
         socket |> put_flash(:info, "#{member.email} is now a #{member.role}.") |> load()}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("resend", %{"id" => id}, socket) do
    %{current_scope: scope, album: album} = socket.assigns

    case Members.resend(scope, album, member!(socket, id)) do
      {:ok, member} ->
        {:noreply,
         socket |> put_flash(:info, "Invitation sent again to #{member.email}.") |> load()}

      {:error, :already_joined} ->
        {:noreply, load(socket)}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    %{current_scope: scope, album: album} = socket.assigns
    {:ok, member} = Members.remove(scope, album, member!(socket, id))
    {:noreply, socket |> put_flash(:info, "#{member.email} removed.") |> load()}
  end

  defp member!(socket, id),
    do: Enum.find(socket.assigns.members, &(&1.id == id)) || raise(Keepsakes.Albums.NotAllowed)

  defp load(socket) do
    %{current_scope: scope, album: album} = socket.assigns

    assign(socket,
      members: Members.list(scope, album),
      seats_used: Members.seats_used(scope),
      seat_limit: Members.seat_limit(scope)
    )
  end

  defp seats_text(_used, :unlimited), do: "Unlimited collaborators"
  defp seats_text(_used, 0), do: ""

  defp seats_text(used, limit),
    do:
      "#{used} of #{limit} collaborator #{if limit == 1, do: "seat", else: "seats"} used, across all your albums"

  defp seat_message({:over_limit, :collaborator_seats, _used, max}),
    do:
      "You've used all #{max} collaborator #{if max == 1, do: "seat", else: "seats"} on your plan. Remove someone or upgrade to invite more."

  defp seat_message(over), do: Entitlements.message(over)
end
