defmodule KeepsakesWeb.SettingsLive.Notifications do
  @moduledoc """
  `/app/settings/notifications`: which emails to get. Receipts, payment
  problems and security emails always send; these switches save as they
  change.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.SettingsComponents

  alias Keepsakes.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <.settings_shell
      flash={@flash}
      current_scope={@current_scope}
      owner={@owner}
      tab={:notifications}
      title="Notifications"
      subtitle="Choose which emails we send you."
    >
      <.settings_card id="notifications" title="Email">
        <.form
          for={@form}
          id="notifications-form"
          phx-change="save"
          class="flex flex-col divide-y divide-base-300"
        >
          <.switch
            field={@form[:notify_guest_activity]}
            label="Guest activity"
            hint="A morning email when your shared albums were opened the day before."
          />
          <.switch
            field={@form[:notify_billing_reminders]}
            label="Billing reminders"
            hint="A heads-up before your trial ends and before a plan renews."
          />
          <.switch
            field={@form[:notify_product_news]}
            label="Product news and tips"
            hint="New templates and features, now and then."
          />
        </.form>
        <p class="text-sm text-ks-muted">
          Receipts, payment problems and security emails (like sign-in links) always send.
        </p>
      </.settings_card>
    </.settings_shell>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :hint, :string, required: true

  defp switch(assigns) do
    assigns =
      assign(
        assigns,
        :checked,
        Phoenix.HTML.Form.normalize_value("checkbox", assigns.field.value)
      )

    ~H"""
    <label for={@field.id} class="flex cursor-pointer items-center justify-between gap-4 py-3.5">
      <span class="flex flex-col gap-0.5">
        <span class="text-[15px] font-medium">{@label}</span>
        <span class="text-sm text-ks-muted">{@hint}</span>
      </span>
      <input type="hidden" name={@field.name} value="false" />
      <input
        type="checkbox"
        id={@field.id}
        name={@field.name}
        value="true"
        checked={@checked}
        class="toggle toggle-primary"
      />
    </label>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     assign(socket,
       page_title: "Notifications",
       form: to_form(Accounts.change_notifications(user))
     )}
  end

  @impl true
  def handle_event("save", %{"user" => params}, socket) do
    scope = socket.assigns.current_scope

    case Accounts.update_notifications(scope.user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(
           current_scope: %{scope | user: user},
           form: to_form(Accounts.change_notifications(user))
         )
         |> put_flash(:info, "Saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
