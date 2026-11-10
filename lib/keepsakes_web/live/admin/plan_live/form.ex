defmodule KeepsakesWeb.Admin.PlanLive.Form do
  @moduledoc """
  `admin.<host>/plans/new` and `/plans/:id`: a plan's name, description,
  order, visibility to new buyers, features and prices. Free and Trial
  plans only take name, description and features. A new price replaces
  the old one for new buyers; people already on it keep paying the old
  amount. Needs `plans.manage`.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Billing.{Admin, Features}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:plans}>
      <.link navigate={~p"/plans"} class="mb-4 flex w-fit items-center gap-1 text-sm text-ks-muted">
        <.icon name="hero-arrow-left" class="size-4" /> Plans
      </.link>
      <.header>
        {if @live_action == :new, do: "New plan", else: @plan.name}
        <:subtitle>
          <%= if @plan.kind == "paid" do %>
            Feature changes apply to everyone on this plan straight away.
          <% else %>
            The {@plan.name} plan: name, description and features. Feature changes apply to everyone on it straight away.
          <% end %>
        </:subtitle>
      </.header>

      <.form
        for={@form}
        id="plan-form"
        phx-change="validate"
        phx-submit="save"
        class="flex max-w-4xl flex-col gap-6"
      >
        <section class="grid gap-x-4 rounded-box border border-base-300 bg-base-100 p-5 sm:grid-cols-2">
          <.input field={@form[:name]} label="Name" maxlength="40" required phx-debounce="300" />
          <.input
            :if={@live_action == :new}
            field={@form[:slug]}
            label="Slug (used in links, can't change later)"
            placeholder="e.g. family"
            phx-debounce="300"
            required
          />
          <div class="sm:col-span-2">
            <.input
              field={@form[:description]}
              label="Description"
              maxlength="160"
              phx-debounce="300"
            />
          </div>
          <%= if @plan.kind == "paid" do %>
            <.input field={@form[:position]} type="number" label="Order on the pricing page" min="0" />
            <div class="flex items-end pb-2">
              <.input field={@form[:public]} type="checkbox" label="Show to new buyers" />
            </div>
          <% end %>
        </section>

        <section
          id="plan-features"
          class="flex flex-col gap-3 rounded-box border border-base-300 bg-base-100 p-5"
        >
          <h2 class="font-bold">Features</h2>
          <div class="grid gap-x-6 gap-y-3 md:grid-cols-2">
            <div :for={feature <- @features} class="flex flex-col gap-1.5">
              <%= if feature.kind == :limit do %>
                <label for={"feature-#{feature.key}"} class="text-sm font-medium">
                  {feature.name} <span class="text-ks-muted">({unit_label(feature.unit)})</span>
                </label>
                <div class="flex items-center gap-3">
                  <input
                    type="number"
                    min="0"
                    id={"feature-#{feature.key}"}
                    name={"plan[features][#{feature.key}][value]"}
                    value={feature_value(@params, feature.key)}
                    disabled={unlimited?(@params, feature.key)}
                    class="input h-11 w-36 border-ks-field bg-base-100"
                  />
                  <label class="flex cursor-pointer items-center gap-2 text-sm">
                    <input
                      type="hidden"
                      name={"plan[features][#{feature.key}][unlimited]"}
                      value="false"
                    />
                    <input
                      type="checkbox"
                      id={"feature-#{feature.key}-unlimited"}
                      name={"plan[features][#{feature.key}][unlimited]"}
                      value="true"
                      checked={unlimited?(@params, feature.key)}
                      class="checkbox checkbox-primary checkbox-sm"
                    /> Unlimited
                  </label>
                </div>
              <% else %>
                <label
                  for={"feature-#{feature.key}"}
                  class="flex cursor-pointer items-center justify-between gap-3 py-1.5"
                >
                  <span class="text-sm font-medium">{feature.name}</span>
                  <input type="hidden" name={"plan[features][#{feature.key}][value]"} value="false" />
                  <input
                    type="checkbox"
                    id={"feature-#{feature.key}"}
                    name={"plan[features][#{feature.key}][value]"}
                    value="true"
                    checked={feature_value(@params, feature.key) in [true, "true"]}
                    class="toggle toggle-primary toggle-sm"
                  />
                </label>
              <% end %>
            </div>
          </div>
          <p :for={msg <- errors(@form, :features)} class="text-sm text-error">{msg}</p>
        </section>

        <section
          :if={@plan.kind == "paid"}
          id="plan-prices"
          class="flex flex-col gap-3 rounded-box border border-base-300 bg-base-100 p-5"
        >
          <div>
            <h2 class="font-bold">Prices</h2>
            <p class="text-sm text-ks-muted">
              A new amount is for new buyers; people already paying keep their price. Leave empty to not offer it.
            </p>
          </div>
          <div class="grid gap-4 sm:grid-cols-2">
            <label
              :for={{currency, interval} = slot <- Admin.price_slots()}
              class="flex flex-col gap-1.5"
            >
              <span class="text-sm font-medium">{currency} per {interval}</span>
              <span class="flex items-center gap-2">
                <span class="w-5 text-ks-muted">{if currency == "NGN", do: "₦", else: "$"}</span>
                <input
                  type="text"
                  inputmode="decimal"
                  id={"price-#{Admin.slot_key(slot)}"}
                  name={"plan[prices][#{Admin.slot_key(slot)}]"}
                  value={get_in(@params, ["prices", Admin.slot_key(slot)])}
                  placeholder="Not offered"
                  phx-debounce="300"
                  class="input h-11 w-44 border-ks-field bg-base-100 tabular-nums"
                />
              </span>
            </label>
          </div>
          <p :for={msg <- errors(@form, :prices)} class="text-sm text-error">{msg}</p>
        </section>

        <div class="flex justify-end gap-2.5">
          <.button type="button" navigate={~p"/plans"}>Cancel</.button>
          <.button id="save-plan" variant="primary" phx-disable-with="Saving…">Save plan</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    plan =
      case socket.assigns.live_action do
        :new -> Admin.new_plan()
        :edit -> Admin.get_plan!(socket.assigns.staff_scope, params["id"])
      end

    form_params = Admin.plan_params(plan)

    {:ok,
     socket
     |> assign(
       page_title: if(plan.id, do: plan.name, else: "New plan"),
       plan: plan,
       features: Features.all()
     )
     |> assign_form(form_params, Admin.change_plan(plan, form_params))}
  end

  @impl true
  def handle_event("validate", %{"plan" => params}, socket) do
    params = Map.merge(socket.assigns.params, params)
    changeset = Admin.change_plan(socket.assigns.plan, params)
    {:noreply, assign_form(socket, params, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"plan" => params}, socket) do
    params = Map.merge(socket.assigns.params, params)
    %{staff_scope: scope, plan: plan} = socket.assigns

    result =
      if plan.id,
        do: Admin.update_plan(scope, plan, params),
        else: Admin.create_plan(scope, params)

    case result do
      {:ok, saved} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved the #{saved.name} plan.")
         |> push_navigate(to: ~p"/plans")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, params, changeset)}
    end
  end

  defp assign_form(socket, params, changeset) do
    assign(socket, params: params, form: to_form(changeset, as: :plan))
  end

  defp feature_value(params, key), do: get_in(params, ["features", to_string(key), "value"])

  defp unlimited?(params, key),
    do: get_in(params, ["features", to_string(key), "unlimited"]) in [true, "true"]

  defp errors(form, field) do
    form.source.errors
    |> Keyword.get_values(field)
    |> Enum.map(fn {msg, _opts} -> msg end)
  end

  defp unit_label(:bytes), do: "GB"
  defp unit_label(:mb), do: "MB per photo"
  defp unit_label(:count), do: "how many"
end
