defmodule KeepsakesWeb.Admin.TemplateLive.Form do
  @moduledoc """
  `admin.<host>/templates/new` and `/templates/:id`: a template's name,
  renderer, premium/visible switches, order, and theme (colours as
  `#RRGGBB`, fonts, light or dark), with a live preview. Empty colours use
  the renderer's own. Needs `templates.manage`.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Templates
  alias Keepsakes.Templates.{Admin, Theme}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:templates}>
      <.link
        navigate={~p"/templates"}
        class="mb-4 flex w-fit items-center gap-1 text-sm text-ks-muted"
      >
        <.icon name="hero-arrow-left" class="size-4" /> Templates
      </.link>
      <.header>
        {if @live_action == :new, do: "New template", else: @template.name}
        <:subtitle>Changes show on every album using this template straight away.</:subtitle>
      </.header>

      <div class="grid gap-6 xl:grid-cols-[minmax(0,1fr)_340px]">
        <.form
          for={@form}
          id="template-form"
          phx-change="validate"
          phx-submit="save"
          class="flex flex-col gap-5"
        >
          <section class="grid gap-x-4 rounded-box border border-base-300 bg-base-100 p-5 sm:grid-cols-2">
            <.input field={@form[:name]} label="Name" maxlength="40" required phx-debounce="300" />
            <.input
              :if={@live_action == :new}
              field={@form[:slug]}
              label="Slug (can't change later)"
              placeholder="e.g. daylight"
              required
              phx-debounce="300"
            />
            <div class="sm:col-span-2">
              <.input
                field={@form[:description]}
                label="Description"
                maxlength="160"
                phx-debounce="300"
              />
            </div>
            <.input
              field={@form[:renderer]}
              type="select"
              label="Renderer"
              options={Enum.map(Templates.renderers(), &{String.capitalize(&1), &1})}
            />
            <.input field={@form[:position]} type="number" label="Order in the gallery" min="0" />
            <.input
              field={@form[:premium]}
              type="checkbox"
              label="Premium (needs a plan with premium templates)"
            />
            <.input field={@form[:active]} type="checkbox" label="Visible to customers" />
          </section>

          <section
            id="theme-fields"
            class="flex flex-col gap-4 rounded-box border border-base-300 bg-base-100 p-5"
          >
            <div>
              <h2 class="font-bold">Theme</h2>
              <p class="text-sm text-ks-muted">
                Colours as #RRGGBB. Leave one empty to use the renderer's.
              </p>
            </div>
            <.input
              name="template[theme][scheme]"
              id="theme-scheme"
              type="select"
              label="Light or dark"
              value={@theme["scheme"] || "dark"}
              options={[{"Dark", "dark"}, {"Light", "light"}]}
            />
            <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              <label :for={{slot, label} <- @colors} for={"theme-#{slot}"} class="flex flex-col gap-1">
                <span class="text-sm font-medium">{label}</span>
                <span class="flex items-center gap-2">
                  <span
                    class="size-7 shrink-0 rounded-field border border-base-300 bg-base-200"
                    style={swatch(@theme[slot])}
                  />
                  <input
                    type="text"
                    id={"theme-#{slot}"}
                    name={"template[theme][#{slot}]"}
                    value={@theme[slot]}
                    placeholder="default"
                    maxlength="9"
                    phx-debounce="300"
                    class="input input-sm h-9 w-full border-ks-field bg-base-100 font-mono"
                  />
                </span>
              </label>
            </div>
            <div class="grid gap-3 sm:grid-cols-2">
              <.input
                :for={{slot, label} <- @fonts}
                name={"template[theme][#{slot}]"}
                id={"theme-#{slot}"}
                type="select"
                label={label}
                value={@theme[slot]}
                prompt="Renderer's default"
                options={Enum.sort(Theme.families())}
              />
            </div>
            <p :for={msg <- errors(@form, :theme)} class="text-sm text-error">{msg}</p>
          </section>

          <p :for={msg <- errors(@form, :active)} id="active-error" class="text-sm text-error">
            {msg}
          </p>

          <div class="flex justify-end gap-2.5">
            <.button type="button" navigate={~p"/templates"}>Cancel</.button>
            <.button id="save-template" variant="primary" phx-disable-with="Saving…">Save template</.button>
          </div>
        </.form>

        <aside class="xl:sticky xl:top-24 xl:self-start">
          <p class="mb-2 text-sm font-medium">Preview</p>
          <div
            id="template-preview"
            style={Theme.css_vars(@theme)}
            class={[
              "flex flex-col items-center gap-4 rounded-box bg-ks-guest p-6 text-center",
              Theme.scheme(@theme) == "light" && "[color-scheme:light]"
            ]}
          >
            <p class="font-display text-2xl font-bold text-ks-guest-ink">Our Little One</p>
            <p class="text-sm text-ks-guest-text">12 memories · Apr 2019 – Sep 2021</p>
            <div class="w-44 -rotate-3 rounded-sm bg-ks-guest-paper p-2.5 pb-3 shadow-[0_12px_28px_var(--color-ks-guest-shadow,rgba(0,0,0,0.4))]">
              <div class="h-28 rounded-[2px] bg-ks-guest-card"></div>
              <p class="pt-2 font-hand text-xl text-ks-ink">First birthday</p>
            </div>
            <div class="h-1.5 w-40 overflow-hidden rounded-full bg-ks-guest-line">
              <div class="h-full w-2/3 bg-ks-guest-bar"></div>
            </div>
            <span class="btn btn-sm rounded-field border-0 bg-primary text-primary-content">
              Play slideshow
            </span>
          </div>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.staff_scope

    template =
      case socket.assigns.live_action do
        :new -> Admin.new_template()
        :edit -> Admin.get!(scope, params["id"])
      end

    {colors, fonts} = Admin.theme_fields()

    {:ok,
     socket
     |> assign(
       page_title: template.name || "New template",
       template: template,
       colors: colors,
       fonts: fonts
     )
     |> assign_form(Admin.change(template), template.theme)}
  end

  @impl true
  def handle_event("validate", %{"template" => params}, socket) do
    changeset = Admin.change(socket.assigns.template, params)

    {:noreply,
     assign_form(socket, Map.put(changeset, :action, :validate), params["theme"] || %{})}
  end

  def handle_event("save", %{"template" => params}, socket) do
    %{staff_scope: scope, template: template} = socket.assigns

    result =
      if template.id, do: Admin.update(scope, template, params), else: Admin.create(scope, params)

    case result do
      {:ok, saved} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved the #{saved.name} template.")
         |> push_navigate(to: ~p"/templates")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset, params["theme"] || %{})}
    end
  end

  defp assign_form(socket, changeset, theme) do
    # Only the slots that are set, so the preview shows the renderer's look for the rest
    theme = theme |> Enum.reject(fn {_k, v} -> v in [nil, ""] end) |> Map.new()
    assign(socket, form: to_form(changeset), theme: theme)
  end

  defp swatch(value) when is_binary(value) do
    if Theme.errors(%{"page" => value}) == [], do: "background: #{value}", else: nil
  end

  defp swatch(_), do: nil

  defp errors(form, field) do
    form.source.errors |> Keyword.get_values(field) |> Enum.map(fn {msg, _} -> msg end)
  end
end
