defmodule KeepsakesWeb.SettingsLive.Templates do
  @moduledoc "`/app/settings/templates`: the template new albums start with."
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.SettingsComponents
  import KeepsakesWeb.TemplateComponents

  alias Keepsakes.Templates

  @impl true
  def render(assigns) do
    ~H"""
    <.settings_shell
      flash={@flash}
      current_scope={@current_scope}
      owner={@owner}
      tab={:templates}
      title="Templates"
      subtitle="New albums start with this look for guests. You can change any album's template from its page."
    >
      <div id="default-template" class="grid gap-5 sm:grid-cols-2">
        <.template_card
          :for={template <- @templates}
          id={"default-#{template.slug}"}
          template={template}
          current={template.id == @default.id}
          title="Your new album"
        >
          <:actions>
            <%= cond do %>
              <% template.id == @default.id -> %>
                <span class="text-sm font-bold text-primary">Used for new albums</span>
              <% template.premium and not @premium? -> %>
                <.button
                  id={"upgrade-default-#{template.slug}"}
                  size="sm"
                  navigate={~p"/app/settings/billing"}
                >
                  Upgrade to use
                </.button>
              <% true -> %>
                <.button
                  id={"use-default-#{template.slug}"}
                  size="sm"
                  variant="primary"
                  phx-click="set_default"
                  phx-value-slug={template.slug}
                >
                  Use for new albums
                </.button>
            <% end %>
          </:actions>
        </.template_card>
      </div>
    </.settings_shell>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     assign(socket,
       page_title: "Templates",
       templates: Templates.list_templates(scope),
       premium?: Templates.premium?(scope),
       default: Templates.default_for(scope)
     )}
  end

  @impl true
  def handle_event("set_default", %{"slug" => slug}, socket) do
    scope = socket.assigns.current_scope

    with %{} = template <- Templates.get_template(scope, slug),
         {:ok, user} <- Templates.set_default_template(scope, template) do
      {:noreply,
       socket
       |> assign(current_scope: %{scope | user: user}, default: template)
       |> put_flash(:info, "New albums will use #{template.name}.")}
    else
      {:error, :premium} ->
        {:noreply, put_flash(socket, :error, "Premium templates need the Plus or Pro plan.")}

      _ ->
        {:noreply, put_flash(socket, :error, "That template isn't available.")}
    end
  end
end
