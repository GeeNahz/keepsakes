defmodule KeepsakesWeb.Admin.ErrorLive.Index do
  @moduledoc """
  `admin.<host>/errors`: errors the app recorded (ErrorTracker), most
  recent first, with how often each happened. Unresolved by default;
  filter by status or search. Needs `errors.view` (`Keepsakes.Errors`).
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Errors

  @limit 100

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:errors}>
      <.header>
        Errors
        <:subtitle>
          Crashes the app recorded, grouped by where they happened. A resolved
          error reopens itself if it happens again.
        </:subtitle>
      </.header>

      <.form
        for={@filters}
        id="error-filters"
        phx-change="filter"
        class="mb-4 flex flex-wrap items-end gap-3"
      >
        <div class="w-48">
          <.input
            field={@filters[:status]}
            type="select"
            label="Status"
            options={[{"Unresolved", "unresolved"}, {"Resolved", "resolved"}, {"All", "all"}]}
          />
        </div>
        <div class="w-72">
          <.input
            field={@filters[:search]}
            type="search"
            label="Search"
            placeholder="Message, kind or source…"
            phx-debounce="300"
          />
        </div>
      </.form>

      <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
        <table class="table">
          <thead>
            <tr>
              <th>Error</th>
              <th>Times</th>
              <th>Last seen (UTC)</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody id="errors" phx-update="stream">
            <tr id="errors-empty" class="hidden only:table-row">
              <td colspan="4" class="py-10 text-center text-ks-muted">
                No errors here. <span :if={@status == "unresolved"}>Nothing needs looking at.</span>
              </td>
            </tr>
            <tr
              :for={{id, {error, count}} <- @streams.errors}
              id={id}
              class="align-top transition-colors hover:bg-base-200"
            >
              <td class="max-w-xl">
                <.link
                  navigate={~p"/errors/#{error.id}"}
                  id={"error-link-#{error.id}"}
                  class="font-mono text-[13px] font-bold text-primary hover:underline"
                >
                  {error.kind}
                </.link>
                <p class="mt-0.5 line-clamp-2 break-words text-sm">{error.reason}</p>
                <p
                  :if={ErrorTracker.Error.has_source_info?(error)}
                  class="mt-0.5 truncate font-mono text-xs text-ks-muted"
                >
                  {error.source_function} · {error.source_line}
                </p>
              </td>
              <td class="font-mono text-[13px]">{count}</td>
              <td class="whitespace-nowrap font-mono text-[13px]">
                <time datetime={DateTime.to_iso8601(error.last_occurrence_at)}>
                  {Calendar.strftime(error.last_occurrence_at, "%d %b %Y, %H:%M")}
                </time>
              </td>
              <td>
                <div class="flex flex-wrap gap-1">
                  <.error_status status={error.status} />
                  <span :if={error.muted} class="badge badge-ghost badge-sm">Muted</span>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p :if={@count == @limit} class="mt-3 text-sm text-ks-muted">
        Showing the latest {@limit}. Search to narrow it down.
      </p>
    </Layouts.app>
    """
  end

  attr :status, :atom, required: true

  @doc false
  def error_status(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      if(@status == :resolved, do: "badge-success badge-soft", else: "badge-warning badge-soft")
    ]}>
      {if @status == :resolved, do: "Resolved", else: "Unresolved"}
    </span>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Errors", limit: @limit)
     # Rows are {error, count} pairs
     |> stream_configure(:errors, dom_id: fn {error, _count} -> "error-#{error.id}" end)
     |> load(%{"status" => "unresolved", "search" => ""})}
  end

  @impl true
  def handle_event("filter", %{"errors" => params}, socket) do
    {:noreply, load(socket, Map.take(params, ["status", "search"]))}
  end

  defp load(socket, filters) do
    errors = Errors.list(socket.assigns.staff_scope, filters, @limit)

    socket
    |> assign(
      filters: to_form(filters, as: :errors),
      status: filters["status"],
      count: length(errors)
    )
    |> stream(:errors, errors, reset: true)
  end
end
