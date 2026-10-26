defmodule KeepsakesWeb.Admin.DiscountLive.Index do
  @moduledoc """
  `admin.<host>/discounts`: every discount code with what it gives, how
  many people used it, its expiry and plans, and how much it has taken off
  paid invoices. Needs `discounts.manage`.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Billing.{Admin, DiscountCode, Price}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:discounts}>
      <.header>
        Discount codes
        <:subtitle>
          Codes customers type at checkout. Turn a code off instead of deleting it.
        </:subtitle>
        <:actions>
          <.button id="new-discount" variant="primary" navigate={~p"/discounts/new"}>
            <.icon name="hero-plus" class="size-4" /> New code
          </.button>
        </:actions>
      </.header>

      <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
        <table class="table">
          <thead>
            <tr>
              <th>Code</th>
              <th>Gives</th>
              <th class="text-right">Used</th>
              <th>Expires</th>
              <th>Taken off</th>
              <th><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody id="discounts" phx-update="stream">
            <tr id="discounts-empty" class="hidden only:table-row">
              <td colspan="6" class="py-10 text-center text-ks-muted">No codes yet.</td>
            </tr>
            <tr :for={{id, {code, discounted}} <- @streams.discounts} id={id}>
              <td>
                <span class="font-mono font-bold">{code.code}</span>
                <.badge :if={!code.active} variant="muted" class="ml-1.5">Off</.badge>
                <p :if={code.description} class="text-sm text-ks-muted">{code.description}</p>
              </td>
              <td>
                <p>{DiscountCode.summary(code)}</p>
                <p class="text-sm text-ks-muted">
                  {if code.plan_slugs == [],
                    do: "Every paid plan",
                    else: Enum.join(code.plan_slugs, ", ")}
                </p>
              </td>
              <td class="text-right tabular-nums">
                {code.redemptions_count}{if code.max_redemptions, do: " / #{code.max_redemptions}"}
              </td>
              <td class="whitespace-nowrap font-mono text-[13px]">
                {if code.expires_at, do: Calendar.strftime(code.expires_at, "%d %b %Y"), else: "Never"}
              </td>
              <td class="whitespace-nowrap tabular-nums">
                <%= if discounted == %{} do %>
                  <span class="text-ks-muted">—</span>
                <% else %>
                  <span :for={{currency, minor} <- Enum.sort(discounted)} class="block">
                    {Price.format(currency, minor)}
                  </span>
                <% end %>
              </td>
              <td class="w-0">
                <.link
                  id={"edit-discount-#{code.id}"}
                  navigate={~p"/discounts/#{code.id}"}
                  class="text-sm font-bold text-primary"
                >
                  Edit
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Discount codes")
     |> stream_configure(:discounts, dom_id: fn {code, _} -> "discounts-#{code.id}" end)
     |> stream(:discounts, Admin.list_codes(socket.assigns.staff_scope))}
  end
end
