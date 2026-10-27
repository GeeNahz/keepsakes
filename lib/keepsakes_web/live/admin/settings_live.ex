defmodule KeepsakesWeb.Admin.SettingsLive do
  @moduledoc """
  `admin.<host>/settings`: every system setting, grouped, edited by type,
  with "Reset to default" where it's been changed. The Maintenance group
  also gives staff a link to look at the site while it's closed. Needs
  `config.manage`.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Settings
  alias Keepsakes.Settings.Admin

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:settings}>
      <.header>
        System settings
        <:subtitle>Changes apply straight away for everyone.</:subtitle>
      </.header>

      <div
        :if={@values[:maintenance_mode]}
        id="maintenance-on"
        class="mb-6 flex flex-wrap items-center justify-between gap-3 rounded-box bg-ks-amber-soft p-4 text-ks-amber-deep"
      >
        <p class="flex items-center gap-2 font-medium">
          <.icon name="hero-wrench-screwdriver" class="size-5" />
          Maintenance mode is on: customers and guests see the maintenance page.
        </p>
        <.button
          id="maintenance-bypass"
          size="sm"
          variant="outline"
          href={@bypass_url}
          target="_blank"
        >
          View the site anyway
        </.button>
      </div>

      <.form for={@form} id="settings-form" phx-submit="save" class="flex max-w-3xl flex-col gap-5">
        <section
          :for={{title, keys} <- Settings.groups()}
          id={"settings-#{slug(title)}"}
          class="flex flex-col gap-3 rounded-box border border-base-300 bg-base-100 p-5"
        >
          <h2 class="font-bold">{title}</h2>
          <div :for={key <- keys} class="flex flex-col gap-1">
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0 flex-1">
                <.setting_input
                  key={key}
                  type={type(key)}
                  value={@values[key]}
                  templates={@templates}
                  error={@errors[key]}
                />
              </div>
              <button
                :if={key in @overridden}
                type="button"
                id={"reset-#{key}"}
                phx-click="reset"
                phx-value-key={key}
                class="mt-7 shrink-0 cursor-pointer text-sm font-bold text-primary"
              >
                Reset to default
              </button>
            </div>
            <p class="text-sm text-ks-muted">
              {description(key)} <span class="text-xs">(default: {default_text(key)})</span>
            </p>
          </div>
        </section>
        <div class="flex justify-end">
          <.button id="save-settings" variant="primary" phx-disable-with="Saving…">Save settings</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  attr :key, :atom, required: true
  attr :type, :atom, required: true
  attr :value, :any, required: true
  attr :templates, :list, required: true
  attr :error, :any, default: nil

  defp setting_input(%{key: :default_template} = assigns) do
    ~H"""
    <.input
      name="settings[default_template]"
      id="setting-default_template"
      type="select"
      label={label(@key)}
      value={@value}
      options={Enum.map(@templates, &{&1.name, &1.slug})}
    />
    """
  end

  defp setting_input(%{type: :boolean} = assigns) do
    ~H"""
    <div class="pt-1">
      <input type="hidden" name={"settings[#{@key}]"} value="false" />
      <label for={"setting-#{@key}"} class="flex cursor-pointer items-center gap-3">
        <input
          type="checkbox"
          id={"setting-#{@key}"}
          name={"settings[#{@key}]"}
          value="true"
          checked={@value}
          class="toggle toggle-primary"
        />
        <span class="font-medium">{label(@key)}</span>
      </label>
    </div>
    """
  end

  defp setting_input(assigns) do
    ~H"""
    <.input
      name={"settings[#{@key}]"}
      id={"setting-#{@key}"}
      type={if(@type == :integer, do: "number", else: "text")}
      min={@type == :integer && "0"}
      label={label(@key)}
      value={@value}
      errors={if(@error, do: ["Enter a valid value"], else: [])}
    />
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    templates = Keepsakes.Templates.Admin.default_choices()

    {:ok,
     socket
     |> assign(
       page_title: "System settings",
       templates: templates,
       errors: %{},
       bypass_url: KeepsakesWeb.Maintenance.bypass_url(socket.assigns.staff_scope.user)
     )
     |> load()}
  end

  @impl true
  def handle_event("save", %{"settings" => params}, socket) do
    case Admin.save(socket.assigns.staff_scope, params) do
      {:ok, []} ->
        {:noreply, put_flash(socket, :info, "Nothing changed.")}

      {:ok, changed} ->
        {:noreply,
         socket
         |> assign(errors: %{})
         |> load()
         |> put_flash(
           :info,
           "Saved #{length(changed)} #{if length(changed) == 1, do: "setting", else: "settings"}."
         )}

      {:error, errors} ->
        {:noreply,
         socket
         |> assign(errors: errors)
         |> put_flash(:error, "Some values weren't valid; nothing was saved.")}
    end
  end

  def handle_event("reset", %{"key" => key}, socket) do
    key = Enum.find(Keyword.keys(Settings.definitions()), &(to_string(&1) == key))
    :ok = Admin.reset(socket.assigns.staff_scope, key)
    {:noreply, socket |> load() |> put_flash(:info, "#{label(key)} is back to its default.")}
  end

  defp load(socket) do
    keys = Keyword.keys(Settings.definitions())

    assign(socket,
      values: Map.new(keys, &{&1, Settings.get(&1)}),
      overridden: Enum.filter(keys, &Settings.overridden?/1),
      form: to_form(%{}, as: :settings)
    )
  end

  defp type(key), do: key |> definition() |> elem(0)
  defp description(key), do: key |> definition() |> elem(2)

  defp default_text(key) do
    case definition(key) do
      {:boolean, true, _} -> "on"
      {:boolean, false, _} -> "off"
      {_type, default, _} -> to_string(default)
    end
  end

  defp definition(key), do: Keyword.fetch!(Settings.definitions(), key)

  @labels %{
    trial_days: "Free trial (days)",
    grace_days: "Grace period (days)",
    image_long_edge: "Photo size (pixels, long edge)",
    image_quality: "Photo quality (1–100)",
    max_upload_mb: "Largest upload (MB)",
    signups_open: "New sign-ups open",
    maintenance_mode: "Maintenance mode",
    maintenance_message: "Maintenance message",
    default_template: "Default template for new albums",
    sla_urgent_hours: "Urgent (hours)",
    sla_high_hours: "High (hours)",
    sla_normal_hours: "Normal (hours)",
    sla_low_hours: "Low (hours)"
  }

  defp label(key), do: Map.get(@labels, key, key |> to_string() |> String.replace("_", " "))

  defp slug(title), do: title |> String.downcase() |> String.replace(~r/[^a-z]+/, "-")
end
