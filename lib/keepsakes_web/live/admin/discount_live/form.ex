defmodule KeepsakesWeb.Admin.DiscountLive.Form do
  @moduledoc """
  `admin.<host>/discounts/new` and `/discounts/:id`: a code, what it
  gives (percent off, for how long), limits (uses, expiry, plans) and
  whether it's on. Once someone has used a code, what it gives is locked
  so their deal doesn't change; limits and on/off stay editable. Needs
  `discounts.manage`.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Billing.{Admin, DiscountCode}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:discounts}>
      <.link
        navigate={~p"/discounts"}
        class="mb-4 flex w-fit items-center gap-1 text-sm text-ks-muted"
      >
        <.icon name="hero-arrow-left" class="size-4" /> Discount codes
      </.link>
      <.header>
        {if @live_action == :new, do: "New discount code", else: @code.code}
        <:subtitle :if={@locked}>
          Used {@code.redemptions_count} {if @code.redemptions_count == 1, do: "time", else: "times"}, so what it gives is locked. You can still change its limits or turn it off.
        </:subtitle>
      </.header>

      <.form
        for={@form}
        id="discount-form"
        phx-change="validate"
        phx-submit="save"
        class="flex max-w-2xl flex-col gap-5 rounded-box border border-base-300 bg-base-100 p-5"
      >
        <div class="grid gap-x-4 sm:grid-cols-2">
          <.input
            field={@form[:code]}
            label="Code"
            placeholder="e.g. LAUNCH20"
            disabled={@locked}
            phx-debounce="300"
            required
          />
          <.input
            field={@form[:percent_off]}
            type="number"
            label="Percent off"
            min="1"
            max="100"
            disabled={@locked}
            required
          />
          <.input
            field={@form[:duration]}
            type="select"
            label="For"
            options={[
              {"The first payment", "once"},
              {"A number of months", "repeating"},
              {"As long as they keep the plan", "forever"}
            ]}
            disabled={@locked}
          />
          <.input
            :if={duration(@form) == "repeating"}
            field={@form[:duration_months]}
            type="number"
            label="Months"
            min="1"
            disabled={@locked}
          />
        </div>
        <.input
          field={@form[:description]}
          label="Note (staff only)"
          maxlength="160"
          phx-debounce="300"
        />
        <div class="grid gap-x-4 sm:grid-cols-2">
          <.input
            field={@form[:max_redemptions]}
            type="number"
            label="Most uses (empty: no limit)"
            min="1"
          />
          <.input
            field={@form[:expires_at]}
            type="date"
            label="Last day it works (empty: never)"
            value={expiry_value(@form)}
          />
        </div>

        <fieldset class="flex flex-col gap-2">
          <legend class="mb-1.5 text-sm font-medium">Plans (none ticked: every paid plan)</legend>
          <input type="hidden" name="discount[plan_slugs][]" value="" />
          <label :for={{name, slug} <- @plans} class="flex cursor-pointer items-center gap-2.5">
            <input
              type="checkbox"
              id={"discount-plan-#{slug}"}
              name="discount[plan_slugs][]"
              value={slug}
              checked={slug in (@form[:plan_slugs].value || [])}
              class="checkbox checkbox-primary checkbox-sm"
            />
            <span>{name}</span>
          </label>
        </fieldset>

        <.input field={@form[:active]} type="checkbox" label="On (customers can use it)" />

        <p class="rounded-field bg-base-200 p-3 text-sm text-ks-muted" id="discount-summary">
          {summary(@form)}
        </p>

        <div class="flex justify-end gap-2.5">
          <.button type="button" navigate={~p"/discounts"}>Cancel</.button>
          <.button id="save-discount" variant="primary" phx-disable-with="Saving…">Save code</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    code =
      case socket.assigns.live_action do
        :new -> %DiscountCode{duration: "once", active: true}
        :edit -> Admin.get_code!(socket.assigns.staff_scope, params["id"])
      end

    {:ok,
     socket
     |> assign(
       page_title: code.code || "New discount code",
       code: code,
       locked: Admin.locked?(code),
       plans: Admin.code_plan_options()
     )
     |> assign(:form, to_form(Admin.change_code(code), as: :discount))}
  end

  @impl true
  def handle_event("validate", %{"discount" => params}, socket) do
    changeset = Admin.change_code(socket.assigns.code, params)

    {:noreply,
     assign(socket, :form, to_form(Map.put(changeset, :action, :validate), as: :discount))}
  end

  def handle_event("save", %{"discount" => params}, socket) do
    %{staff_scope: scope, code: code} = socket.assigns

    result =
      if code.id,
        do: Admin.update_code(scope, code, params),
        else: Admin.create_code(scope, params)

    case result do
      {:ok, saved} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved #{saved.code}.")
         |> push_navigate(to: ~p"/discounts")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :discount))}
    end
  end

  defp duration(form), do: Ecto.Changeset.get_field(form.source, :duration)

  defp expiry_value(form) do
    case Ecto.Changeset.get_field(form.source, :expires_at) do
      %DateTime{} = at -> at |> DateTime.to_date() |> Date.to_iso8601()
      _ -> nil
    end
  end

  defp summary(form) do
    code = Ecto.Changeset.apply_changes(form.source)

    if is_integer(code.percent_off) and code.duration in ~w(once repeating forever) and
         (code.duration != "repeating" or is_integer(code.duration_months)),
       do: "Customers see: " <> DiscountCode.summary(code),
       else: "Fill in the percent and how long it lasts."
  end
end
