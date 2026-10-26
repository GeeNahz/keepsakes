defmodule KeepsakesWeb.Admin.AuditLive.Index do
  @moduledoc """
  `admin.<host>/audit`: every change made in the admin portal, newest
  first: who, what, to which record, the before/after values and the IP.
  Filter by section or by who did it. Read-only. Needs `audit.view`.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Audit

  @limit 200

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:audit}>
      <.header>
        Audit log
        <:subtitle>Every change made in the admin portal. Entries can't be edited.</:subtitle>
      </.header>

      <.form
        for={@filters}
        id="audit-filters"
        phx-change="filter"
        class="mb-4 flex flex-wrap items-end gap-3"
      >
        <div class="w-48">
          <.input
            field={@filters[:action]}
            type="select"
            label="Section"
            prompt="Everything"
            options={@groups}
          />
        </div>
        <div class="w-64">
          <.input
            field={@filters[:actor]}
            type="search"
            label="Done by"
            placeholder="Email contains…"
            phx-debounce="300"
          />
        </div>
      </.form>

      <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
        <table class="table">
          <thead>
            <tr>
              <th>When (UTC)</th>
              <th>Who</th>
              <th>What</th>
              <th>Details</th>
            </tr>
          </thead>
          <tbody id="audit-events" phx-update="stream">
            <tr id="audit-empty" class="hidden only:table-row">
              <td colspan="4" class="py-10 text-center text-ks-muted">Nothing recorded yet.</td>
            </tr>
            <tr :for={{id, e} <- @streams.events} id={id} class="align-top">
              <td class="whitespace-nowrap font-mono text-[13px]">
                <time datetime={DateTime.to_iso8601(e.inserted_at)}>
                  {Calendar.strftime(e.inserted_at, "%d %b %Y, %H:%M")}
                </time>
              </td>
              <td>
                <p class="text-[15px]">{e.actor_email}</p>
                <p :if={e.ip} class="font-mono text-xs text-ks-muted">{e.ip}</p>
              </td>
              <td>
                <p class="font-mono text-[13px] font-bold">{e.action}</p>
                <p :if={e.target_label} class="text-sm text-ks-muted">{e.target_label}</p>
              </td>
              <td class="max-w-md">
                <details :if={e.changes != %{}}>
                  <summary class="cursor-pointer text-sm text-primary">Show changes</summary>
                  <dl class="mt-2 flex flex-col gap-1.5 text-sm">
                    <div :for={{key, value} <- Enum.sort(e.changes)} class="flex flex-col">
                      <dt class="font-medium">{key}</dt>
                      <dd class="break-words font-mono text-xs text-ks-muted">
                        {change_text(value)}
                      </dd>
                    </div>
                  </dl>
                </details>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p :if={@count == @limit} class="mt-3 text-sm text-ks-muted">
        Showing the latest {@limit}. Filter to narrow it down.
      </p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Audit log", limit: @limit, groups: Audit.action_groups())
     |> load(%{"action" => "", "actor" => ""})}
  end

  @impl true
  def handle_event("filter", %{"audit" => params}, socket) do
    {:noreply, load(socket, Map.take(params, ["action", "actor"]))}
  end

  defp load(socket, filters) do
    # A section is the part before the dot ("staff" for "staff.granted")
    query = Map.update(filters, "action", "", &if(&1 == "", do: "", else: &1 <> "."))
    events = Audit.list(socket.assigns.staff_scope, query, @limit)

    socket
    |> assign(filters: to_form(filters, as: :audit), count: length(events))
    |> stream(:events, events, reset: true)
  end

  defp change_text(value) when is_binary(value), do: value
  defp change_text(value) when is_list(value), do: Enum.map_join(value, ", ", &change_text/1)

  defp change_text(value) when is_map(value),
    do: Enum.map_join(Enum.sort(value), "; ", fn {k, v} -> "#{k}: #{change_text(v)}" end)

  defp change_text(value), do: inspect(value)
end
