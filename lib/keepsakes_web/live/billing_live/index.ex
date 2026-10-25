defmodule KeepsakesWeb.BillingLive.Index do
  @moduledoc """
  `/billing`: the owner's plan, what they're using against its limits, and
  the plans side by side in NGN or USD, monthly or yearly. Choosing a paid
  plan opens with Flutterwave checkout in Stage 5b; until then the buttons
  say payments are coming. Becomes the Billing tab of settings in Stage 6.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.{Albums, Billing, Entitlements, Format}
  alias Keepsakes.Billing.{Features, Price}

  # Rows in the plan comparison: the features that are live today
  @compared ~w(max_albums max_memories_per_album storage_bytes max_upload_mb
               premium_templates guest_downloads remove_branding)a

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} owner={@owner}>
      <div class="mx-auto flex w-full max-w-[1040px] flex-col gap-8">
        <div class="flex flex-col gap-1.5">
          <h1 class="text-[32px] font-bold">Plans &amp; billing</h1>
          <p class="text-base text-ks-muted">
            Your plan, what you're using, and what each plan includes.
          </p>
        </div>

        <section
          id="current-plan"
          aria-label="Your plan"
          class="grid gap-6 rounded-2xl border border-base-300 bg-base-100 p-7 md:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)]"
        >
          <div class="flex flex-col gap-2">
            <span class="text-sm font-bold uppercase tracking-[0.06em] text-ks-muted">Your plan</span>
            <span id="current-plan-name" class="text-2xl font-bold">{@plan.name}</span>
            <span
              :if={Billing.status_detail(@subscription)}
              id="current-plan-status"
              class="text-[15px] font-medium text-primary"
            >
              {Billing.status_detail(@subscription)}
            </span>
            <p class="text-sm leading-relaxed text-ks-muted">{plan_note(@subscription)}</p>
          </div>

          <div id="usage" class="flex flex-col gap-4">
            <.usage_row
              id="usage-storage"
              label="Storage"
              used={@usage.storage_bytes}
              limit={@limits.storage_bytes}
              format={&Format.bytes/1}
            />
            <.usage_row
              id="usage-albums"
              label="Albums"
              used={@usage.max_albums}
              limit={@limits.max_albums}
            />
            <.usage_row
              id="usage-photos"
              label="Photos in your largest album"
              used={@usage.max_memories_per_album}
              limit={@limits.max_memories_per_album}
            />
          </div>
        </section>

        <section id="plans" aria-label="Plans" class="flex flex-col gap-5">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <h2 class="text-2xl font-bold">Plans</h2>
            <div class="flex flex-wrap gap-3">
              <.segmented
                id="currency-switch"
                event="currency"
                value={@currency}
                options={[{"NGN", "₦ NGN"}, {"USD", "$ USD"}]}
              />
              <.segmented
                id="interval-switch"
                event="interval"
                value={@interval}
                options={[{"month", "Monthly"}, {"year", "Yearly"}]}
              />
            </div>
          </div>

          <div class="grid gap-5 md:grid-cols-3">
            <.plan_card
              :for={plan <- @plans}
              plan={plan}
              price={Billing.price(plan, @currency, @interval)}
              current={plan.id == @plan.id}
              compared={@compared}
            />
          </div>
          <p class="text-sm text-ks-muted">
            Card payments in naira or dollars open soon. Until then, your trial carries on as normal.
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :used, :integer, required: true
  attr :limit, :any, required: true
  attr :format, :any, default: &Integer.to_string/1

  defp usage_row(%{limit: :unlimited} = assigns) do
    ~H"""
    <div id={@id} class="flex items-center justify-between gap-3 text-sm">
      <span class="font-medium">{@label}</span>
      <span class="text-ks-muted">{@format.(@used)} · unlimited</span>
    </div>
    """
  end

  defp usage_row(assigns) do
    ~H"""
    <.meter
      id={@id}
      label={@label}
      value={min(@used, @limit)}
      max={max(@limit, 1)}
      text={"#{@format.(@used)} of #{@format.(@limit)}"}
    />
    <p :if={@used > @limit} class="-mt-2 text-[13px] text-ks-amber-deep">
      Over the limit: nothing is removed, but you can't add more here.
    </p>
    """
  end

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :value, :string, required: true
  attr :options, :list, required: true

  defp segmented(assigns) do
    ~H"""
    <div
      id={@id}
      role="group"
      class="flex gap-0.5 rounded-full border border-base-300 bg-base-100 p-1"
    >
      <button
        :for={{value, label} <- @options}
        type="button"
        phx-click={@event}
        phx-value-to={value}
        aria-pressed={to_string(value == @value)}
        class="min-h-9 cursor-pointer rounded-full px-3.5 text-sm font-bold text-ks-muted transition-colors aria-pressed:bg-primary aria-pressed:text-primary-content"
      >
        {label}
      </button>
    </div>
    """
  end

  attr :plan, :map, required: true
  attr :price, :any, required: true
  attr :current, :boolean, required: true
  attr :compared, :list, required: true

  defp plan_card(assigns) do
    assigns =
      assign(assigns,
        rows:
          for feature <- assigns.compared do
            value = Features.value(assigns.plan.features, feature.key)
            %{key: feature.key, text: feature_text(feature, value), on?: value not in [false, 0]}
          end
      )

    ~H"""
    <article
      id={"plan-#{@plan.slug}"}
      class={[
        "flex flex-col gap-5 rounded-2xl border bg-base-100 p-6",
        if(@current, do: "border-primary ring-1 ring-primary", else: "border-base-300")
      ]}
    >
      <div class="flex flex-col gap-1.5">
        <div class="flex items-center gap-2">
          <h3 class="text-xl font-bold">{@plan.name}</h3>
          <span :if={@current} class="badge badge-sm badge-primary">Current</span>
        </div>
        <p class="min-h-[2.8em] text-sm text-ks-muted">{@plan.description}</p>
      </div>

      <div class="flex items-baseline gap-1.5">
        <%= if @price do %>
          <span class="text-3xl font-bold">{Price.format(@price)}</span>
          <span class="text-sm text-ks-muted">/ {@price.interval}</span>
        <% else %>
          <span class="text-3xl font-bold">Free</span>
        <% end %>
      </div>

      <ul class="flex flex-col gap-2.5 text-sm">
        <li :for={row <- @rows} id={"plan-#{@plan.slug}-#{row.key}"} class="flex items-start gap-2">
          <.icon
            name={if row.on?, do: "hero-check", else: "hero-minus"}
            class={["mt-0.5 size-4 shrink-0", if(row.on?, do: "text-primary", else: "text-ks-field")]}
          />
          <span class={!row.on? && "text-ks-muted"}>{row.text}</span>
        </li>
      </ul>

      <div class="mt-auto">
        <%= cond do %>
          <% @current -> %>
            <.button id={"choose-#{@plan.slug}"} type="button" class="w-full" disabled>
              Your plan
            </.button>
          <% @price -> %>
            <.button
              id={"choose-#{@plan.slug}"}
              type="button"
              variant="primary"
              class="w-full"
              disabled
            >
              Choose {@plan.name} · soon
            </.button>
          <% true -> %>
        <% end %>
      </div>
    </article>
    """
  end

  defp feature_text(%{key: :max_albums}, :unlimited), do: "Unlimited albums"
  defp feature_text(%{key: :max_albums}, 1), do: "1 album"
  defp feature_text(%{key: :max_albums}, count), do: "#{count} albums"
  defp feature_text(%{key: :max_memories_per_album}, :unlimited), do: "Unlimited photos per album"
  defp feature_text(%{key: :max_memories_per_album}, count), do: "#{count} photos per album"
  defp feature_text(%{key: :storage_bytes}, :unlimited), do: "Unlimited storage"
  defp feature_text(%{key: :storage_bytes}, bytes), do: "#{Format.bytes(bytes)} of storage"
  defp feature_text(%{key: :max_upload_mb}, mb), do: "Photos up to #{mb} MB each"
  defp feature_text(%{name: name}, _value), do: name

  defp plan_note(%{status: "trialing", trial_ends_at: ends_at}),
    do:
      "Everything in Pro until #{date(ends_at)}. After that you get #{Keepsakes.Settings.get(:grace_days)} more days of full access, then the Free plan. Nothing you've added is ever deleted."

  defp plan_note(%{status: "grace", grace_ends_at: ends_at}),
    do:
      "You keep every feature until #{date(ends_at)}, then move to the Free plan. Nothing you've added is deleted."

  defp plan_note(_subscription),
    do: "Change plans any time. Moving to a smaller plan never deletes anything."

  defp date(at), do: Calendar.strftime(at, "%-d %B %Y")

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Plans & billing",
       plans: Billing.list_public_plans(),
       currency: "NGN",
       interval: "month",
       compared: Enum.filter(Features.all(), &(&1.key in @compared))
     )
     |> load_account()}
  end

  defp load_account(socket) do
    scope = socket.assigns.current_scope
    subscription = Billing.get_subscription(scope)
    albums = Albums.list_albums(scope)

    assign(socket,
      subscription: subscription,
      plan: Billing.current_plan(scope),
      limits: Entitlements.all(scope),
      usage: %{
        storage_bytes: socket.assigns.owner.storage_used,
        max_albums: length(albums),
        max_memories_per_album: Albums.largest_album_count(scope)
      }
    )
  end

  @impl true
  def handle_event("currency", %{"to" => currency}, socket) when currency in ~w(NGN USD),
    do: {:noreply, assign(socket, currency: currency)}

  def handle_event("interval", %{"to" => interval}, socket) when interval in ~w(month year),
    do: {:noreply, assign(socket, interval: interval)}
end
