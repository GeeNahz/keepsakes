defmodule KeepsakesWeb.SettingsLive.Domains do
  @moduledoc """
  `/app/settings/domains`: the customer's own domain for their public site.
  Add a domain, see the two DNS records to create (with copy buttons), its
  status and the last check, check again, or remove it; and choose which
  shared albums appear on the site. Shows "Coming soon" until the
  `custom_domains` flag is on for them, and an upgrade prompt when their
  plan has no custom domains.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.SettingsComponents

  alias Keepsakes.Domains
  alias Keepsakes.Domains.Domain

  @impl true
  def render(assigns) do
    ~H"""
    <.settings_shell
      flash={@flash}
      current_scope={@current_scope}
      owner={@owner}
      tab={:domains}
      title="Domains"
      subtitle="Show your albums on your own web address."
    >
      <%= cond do %>
        <%!-- Someone who already has a domain always sees it, to manage or remove --%>
        <% !@flag_on? and @domains == [] -> %>
          <.settings_card id="domains-soon" title="Your own domain">
            <div class="flex flex-col items-start gap-3">
              <.badge variant="muted">Coming soon</.badge>
              <p class="text-[15px] leading-relaxed text-ks-muted">
                Soon you'll be able to open your albums at an address like <span class="font-mono text-base-content">memories.yourfamily.com</span>, with the same access codes.
              </p>
            </div>
          </.settings_card>
        <% !@available? and @domains == [] -> %>
          <.settings_card id="domains-upgrade" title="Your own domain">
            <div class="flex flex-col items-start gap-3">
              <p class="text-[15px] leading-relaxed text-ks-muted">
                Open your albums at your own address, like <span class="font-mono text-base-content">memories.yourfamily.com</span>.
                Custom domains come with the Pro plan.
              </p>
              <.button id="domains-see-plans" variant="primary" navigate={~p"/app/settings/billing"}>
                See plans
              </.button>
            </div>
          </.settings_card>
        <% true -> %>
          <.settings_card
            :for={domain <- @domains}
            id={"domain-#{domain.id}"}
            title={domain.hostname}
          >
            <div class="flex flex-col gap-4">
              <div class="flex flex-wrap items-center gap-2">
                <.domain_status domain={domain} />
                <span :if={domain.last_checked_at} class="text-sm text-ks-muted">
                  Last checked {Calendar.strftime(domain.last_checked_at, "%-d %b, %H:%M")} UTC
                </span>
              </div>
              <p
                :if={domain.last_error && domain.status != "verified"}
                class="rounded-field bg-ks-amber-soft p-3 text-sm text-ks-amber-deep"
              >
                Not yet: {domain.last_error}.
              </p>
              <p :if={domain.status == "blocked"} class="rounded-field bg-base-200 p-3 text-sm">
                This domain was blocked by Keepsake. Contact support if you think that's a mistake.
              </p>
              <p :if={domain.status == "verified"} class="text-[15px]">
                Your site is live at <a
                  href={"https://#{domain.hostname}"}
                  target="_blank"
                  rel="noopener"
                  class="font-bold text-primary"
                >
                  {domain.hostname}
                </a>.
              </p>

              <div :if={domain.status != "verified"} class="flex flex-col gap-2">
                <p class="text-sm font-medium">
                  Add these records where you manage your domain's DNS:
                </p>
                <div class="overflow-x-auto rounded-field border border-base-300">
                  <table class="table table-sm">
                    <thead>
                      <tr>
                        <th>Type</th><th>Name</th><th>Value</th><th></th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr :for={{record, i} <- Enum.with_index(Domains.records(domain))}>
                        <td class="font-mono">{record.type}</td>
                        <td class="font-mono text-sm">{record.name}</td>
                        <td class="font-mono text-sm break-all" id={"record-#{domain.id}-#{i}"}>
                          {record.value}
                        </td>
                        <td class="w-0">
                          <button
                            type="button"
                            class="cursor-pointer text-sm font-bold text-primary"
                            phx-click={
                              JS.dispatch("ks:copy", detail: %{from: "#record-#{domain.id}-#{i}"})
                            }
                          >
                            <span data-copy-label>Copy</span>
                          </button>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
                <p class="text-xs text-ks-muted">
                  DNS changes can take a while to spread. We check automatically and email you when it's connected.
                </p>
              </div>

              <div class="flex flex-wrap gap-2">
                <.button
                  :if={domain.status != "blocked"}
                  id={"check-#{domain.id}"}
                  size="sm"
                  phx-click="check"
                  phx-value-id={domain.id}
                  phx-disable-with="Checking…"
                >
                  Check now
                </.button>
                <.button
                  :if={@confirm_remove != domain.id}
                  id={"remove-#{domain.id}"}
                  size="sm"
                  phx-click="ask_remove"
                  phx-value-id={domain.id}
                >
                  Remove
                </.button>
                <.button
                  :if={@confirm_remove == domain.id}
                  id={"confirm-remove-#{domain.id}"}
                  size="sm"
                  variant="danger"
                  phx-click="remove"
                  phx-value-id={domain.id}
                >
                  Remove {domain.hostname}
                </.button>
              </div>
            </div>
          </.settings_card>

          <.settings_card
            :if={@can_add?}
            id="add-domain"
            title="Add a domain"
            description="Use a domain or subdomain you own, like memories.yourfamily.com."
          >
            <.form
              for={@form}
              id="add-domain-form"
              phx-submit="add"
              class="flex flex-wrap items-start gap-2"
            >
              <div class="w-full max-w-sm">
                <.input
                  field={@form[:hostname]}
                  placeholder="memories.yourfamily.com"
                  autocomplete="off"
                  required
                />
              </div>
              <.button id="add-domain-submit" variant="primary" phx-disable-with="Adding…">Add domain</.button>
            </.form>
            <p :if={@add_error} id="add-domain-error" class="mt-2 text-sm text-error">{@add_error}</p>
          </.settings_card>

          <.settings_card
            id="site-albums"
            title="Albums on your site"
            description="Your site lists the albums you switch on here. Guests still need each album's access code."
          >
            <p :if={@albums == []} class="text-sm text-ks-muted">No albums yet.</p>
            <ul :if={@albums != []} class="flex flex-col divide-y divide-base-300">
              <li
                :for={{album, shared?} <- @albums}
                class="flex items-center justify-between gap-3 py-2.5"
              >
                <span class="min-w-0">
                  <span class="block truncate font-medium">{album.name}</span>
                  <span :if={!shared?} class="text-sm text-ks-muted">Turn on sharing to show it on your site.</span>
                </span>
                <input
                  type="checkbox"
                  id={"show-album-#{album.id}"}
                  class="toggle toggle-primary"
                  checked={album.show_on_site}
                  disabled={!shared?}
                  phx-click="toggle_album"
                  phx-value-id={album.id}
                  aria-label={"Show #{album.name} on my site"}
                />
              </li>
            </ul>
          </.settings_card>
      <% end %>
    </.settings_shell>
    """
  end

  attr :domain, Domain, required: true

  defp domain_status(assigns) do
    ~H"""
    <%= case @domain.status do %>
      <% "verified" -> %>
        <.badge variant="ready">Connected</.badge>
      <% "pending" -> %>
        <.badge variant="pending">Waiting for DNS</.badge>
      <% "failed" -> %>
        <span class="badge h-auto rounded-full border-0 bg-error/15 px-2.5 py-1 text-xs font-bold text-error">
          Not connected
        </span>
      <% "blocked" -> %>
        <.badge variant="muted">Blocked</.badge>
    <% end %>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Domains", confirm_remove: nil, add_error: nil) |> load()}
  end

  @impl true
  def handle_event("add", %{"domain" => %{"hostname" => host}}, socket) do
    case Domains.add(socket.assigns.current_scope, host) do
      {:ok, domain} ->
        {:noreply,
         socket
         |> load()
         |> put_flash(:info, "Added #{domain.hostname}. Now add the DNS records below.")}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           add_error: add_error(reason),
           form: to_form(%{"hostname" => host}, as: :domain)
         )}
    end
  end

  def handle_event("check", %{"id" => id}, socket) do
    domain = Domains.get!(socket.assigns.current_scope, id)
    {:ok, checked} = Domains.check(domain)

    message =
      if checked.status == "verified",
        do: "#{checked.hostname} is connected.",
        else: "Not connected yet: #{checked.last_error}."

    {:noreply, socket |> load() |> put_flash(:info, message)}
  end

  def handle_event("ask_remove", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :confirm_remove, id)}

  def handle_event("remove", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    {:ok, domain} = Domains.remove(scope, Domains.get!(scope, id))

    {:noreply,
     socket
     |> assign(:confirm_remove, nil)
     |> load()
     |> put_flash(:info, "Removed #{domain.hostname}.")}
  end

  def handle_event("toggle_album", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Enum.find(socket.assigns.albums, fn {a, shared?} -> a.id == id and shared? end) do
      {album, true} ->
        {:ok, _} = Domains.show_on_site(scope, album, !album.show_on_site)
        {:noreply, load(socket)}

      _ ->
        {:noreply, socket}
    end
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    domains = Domains.list(scope)
    limit = Keepsakes.Entitlements.limit(scope, :custom_domains)

    assign(socket,
      flag_on?: Domains.flag_on?(scope),
      available?: Domains.available?(scope),
      domains: domains,
      can_add?: Domains.available?(scope) and (limit == :unlimited or length(domains) < limit),
      albums: Domains.site_choices(scope),
      form: to_form(%{"hostname" => ""}, as: :domain)
    )
  end

  defp add_error(:invalid),
    do: "That doesn't look like a domain. Use something like memories.yourfamily.com."

  defp add_error(:ours), do: "That's one of Keepsake's own addresses. Use a domain you own."

  defp add_error(:blocked),
    do: "That domain can't be used. Contact support if you think that's a mistake."

  defp add_error(:taken), do: "That domain is already connected to another account."
  defp add_error(:limit_reached), do: "Your plan's domains are all in use. Remove one or upgrade."
  defp add_error(:not_available), do: "Custom domains aren't available on your plan."
end
