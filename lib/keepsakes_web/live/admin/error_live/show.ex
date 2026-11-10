defmodule KeepsakesWeb.Admin.ErrorLive.Show do
  @moduledoc """
  `admin.<host>/errors/:id`: one error. Its full message, where it
  happened, its recent occurrences, and for the chosen one (the newest by
  default) the stack trace, request context and breadcrumbs. Resolve,
  reopen, mute and unmute need `errors.manage`.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Errors
  alias Keepsakes.Staff.Scope, as: StaffScope
  alias KeepsakesWeb.Admin.ErrorLive.Index

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:errors}>
      <.link
        navigate={~p"/errors"}
        id="errors-back"
        class="mb-3 inline-flex items-center gap-1 text-sm text-primary hover:underline"
      >
        <.icon name="hero-arrow-left" class="size-4" /> All errors
      </.link>

      <.header>
        <span class="font-mono">{@error.kind}</span>
        <:subtitle>
          <span class="inline-flex flex-wrap items-center gap-2">
            <Index.error_status status={@error.status} />
            <span :if={@error.muted} class="badge badge-ghost badge-sm">Muted</span>
            <span class="text-sm">
              {@total} {if @total == 1, do: "time", else: "times"}, last on {Calendar.strftime(
                @error.last_occurrence_at,
                "%d %b %Y at %H:%M UTC"
              )}
            </span>
          </span>
        </:subtitle>
        <:actions :if={@can_manage}>
          <div class="flex flex-wrap gap-2">
            <.button
              :if={@error.status == :unresolved}
              id="error-resolve"
              phx-click="resolve"
              variant="primary"
            >
              <.icon name="hero-check" class="size-4" /> Resolve
            </.button>
            <.button :if={@error.status == :resolved} id="error-reopen" phx-click="reopen">
              Reopen
            </.button>
            <.button id="error-mute" phx-click="mute" phx-value-muted={to_string(!@error.muted)}>
              {if @error.muted, do: "Unmute", else: "Mute"}
            </.button>
          </div>
        </:actions>
      </.header>

      <section id="error-reason" class="mb-6 rounded-box border border-base-300 bg-base-100 p-4">
        <pre class="max-h-72 overflow-y-auto whitespace-pre-wrap break-words font-mono text-[13px]">{@error.reason}</pre>
        <p
          :if={ErrorTracker.Error.has_source_info?(@error)}
          class="mt-3 border-t border-base-300 pt-3 font-mono text-xs text-ks-muted"
        >
          {@error.source_function} · {@error.source_line}
        </p>
      </section>

      <div class="grid gap-6 lg:grid-cols-[16rem_1fr]">
        <nav id="occurrences" aria-label="Occurrences">
          <h2 class="mb-2 text-sm font-semibold">
            Occurrences
            <span :if={@total > length(@occurrences)} class="font-normal text-ks-muted">
              (latest {length(@occurrences)} of {@total})
            </span>
          </h2>
          <ul class="flex flex-col gap-1">
            <li :for={o <- @occurrences}>
              <.link
                patch={~p"/errors/#{@error.id}?occurrence=#{o.id}"}
                id={"occurrence-#{o.id}"}
                class={[
                  "block rounded-field px-3 py-2 font-mono text-[13px] transition-colors",
                  if(@occurrence && @occurrence.id == o.id,
                    do: "bg-ks-teal-soft text-primary",
                    else: "hover:bg-base-200"
                  )
                ]}
              >
                {Calendar.strftime(o.inserted_at, "%d %b, %H:%M:%S")}
              </.link>
            </li>
          </ul>
        </nav>

        <div :if={@occurrence} id="occurrence" class="flex min-w-0 flex-col gap-6">
          <section>
            <h2 class="mb-2 text-sm font-semibold">Stack trace</h2>
            <ol
              id="stacktrace"
              class="overflow-x-auto rounded-box border border-base-300 bg-base-100 font-mono text-xs"
            >
              <li
                :for={line <- stack_lines(@occurrence)}
                class={[
                  "border-b border-base-300 px-3 py-1.5 last:border-b-0",
                  if(own_code?(line), do: "font-bold", else: "text-ks-muted")
                ]}
              >
                <span :if={line.application} class="mr-2 text-ks-muted">({line.application})</span>
                {line_text(line)}
              </li>
            </ol>
          </section>

          <section :if={@occurrence.context not in [nil, %{}]}>
            <h2 class="mb-2 text-sm font-semibold">Context</h2>
            <pre
              id="occurrence-context"
              class="overflow-x-auto rounded-box border border-base-300 bg-base-100 p-3 font-mono text-xs"
            >{Jason.encode!(@occurrence.context, pretty: true)}</pre>
          </section>

          <section :if={@occurrence.breadcrumbs not in [nil, []]}>
            <h2 class="mb-2 text-sm font-semibold">Breadcrumbs</h2>
            <ol class="list-decimal pl-5 font-mono text-xs">
              <li :for={crumb <- @occurrence.breadcrumbs}>{crumb}</li>
            </ol>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.staff_scope
    error = Errors.get!(scope, id)
    {occurrences, total} = Errors.occurrences(scope, error)

    {:ok,
     assign(socket,
       page_title: "Error",
       error: error,
       occurrences: occurrences,
       total: total,
       can_manage: StaffScope.can?(scope, "errors.manage")
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    occurrences = socket.assigns.occurrences

    occurrence =
      Enum.find(occurrences, &(to_string(&1.id) == params["occurrence"])) ||
        List.first(occurrences)

    {:noreply, assign(socket, occurrence: occurrence)}
  end

  @impl true
  def handle_event("resolve", _params, socket),
    do: update_error(socket, &Errors.resolve/2, "Marked as resolved.")

  def handle_event("reopen", _params, socket),
    do: update_error(socket, &Errors.unresolve/2, "Reopened.")

  def handle_event("mute", %{"muted" => muted}, socket) do
    muted? = muted == "true"

    update_error(
      socket,
      &Errors.set_muted(&1, &2, muted?),
      if(muted?, do: "Muted.", else: "Unmuted.")
    )
  end

  defp update_error(socket, fun, message) do
    case fun.(socket.assigns.staff_scope, socket.assigns.error) do
      {:ok, error} -> {:noreply, socket |> assign(error: error) |> put_flash(:info, message)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "That didn't save. Try again.")}
    end
  end

  defp stack_lines(%{stacktrace: %{lines: lines}}) when is_list(lines), do: lines
  defp stack_lines(_occurrence), do: []

  # Our frames stand out. Frames in anonymous functions (inside templates)
  # come without an application, so the module name decides too
  defp own_code?(line) do
    line.application == "keepsakes" or String.starts_with?(line.module || "", "Keepsakes")
  end

  defp line_text(line) do
    call = "#{line.module}.#{line.function}/#{line.arity}"
    if line.file, do: "#{call}  #{line.file}:#{line.line}", else: call
  end
end
