defmodule KeepsakesWeb.Admin.CustomerLive.Show do
  @moduledoc """
  `admin.<host>/customers/:id`: one customer's account in one place
  (plan and its history, usage, albums, tickets, invoices with
  `finance.view`, audit entries with `audit.view`), plus the fixes staff
  with `users.manage` can make, each in a dialog: extend the trial, gift
  free months, give a plan, move to Free, suspend or unsuspend.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.SupportComponents, only: [status_badge: 1]

  alias Keepsakes.Accounts.User
  alias Keepsakes.Billing
  alias Keepsakes.Billing.{PaymentMethod, Price}
  alias Keepsakes.Customers
  alias Keepsakes.Staff.Scope, as: StaffScope

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:customers}>
      <.link
        navigate={~p"/customers"}
        class="mb-4 flex w-fit items-center gap-1 text-sm text-ks-muted"
      >
        <.icon name="hero-arrow-left" class="size-4" /> Customers
      </.link>

      <header id="customer-header" class="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div class="flex items-center gap-4">
          <.avatar
            name={User.full_name(@customer)}
            src={Keepsakes.Accounts.avatar_url(@customer)}
            class="size-14 text-lg"
          />
          <div class="flex flex-col gap-1">
            <h1 class="font-display text-3xl font-bold">{User.full_name(@customer)}</h1>
            <p class="text-ks-muted">{@customer.email}</p>
            <div class="flex flex-wrap gap-1.5">
              <.badge variant="muted">Joined {date(@customer.inserted_at)}</.badge>
              <.badge :if={!@customer.confirmed_at} variant="pending">Email not confirmed</.badge>
              <.badge :if={@customer.totp_enabled_at} variant="ready">Two-step login on</.badge>
              <.badge :if={@customer.suspended_at} variant="pending">
                Suspended
              </.badge>
              <.badge :if={@customer.deletion_requested_at} variant="pending">
                Deletes on {date(Keepsakes.Accounts.deletion_date(@customer))}
              </.badge>
            </div>
          </div>
        </div>

        <div :if={@manage?} id="customer-actions" class="flex flex-wrap gap-2">
          <.button
            :if={Customers.on_trial?(@sub)}
            id="action-extend"
            size="sm"
            phx-click="open"
            phx-value-action="extend"
          >
            Extend trial
          </.button>
          <.button id="action-gift" size="sm" phx-click="open" phx-value-action="gift">
            Gift free months
          </.button>
          <.button
            :if={!Customers.paying?(@sub)}
            id="action-give"
            size="sm"
            phx-click="open"
            phx-value-action="give"
          >
            Give a plan
          </.button>
          <.button
            :if={@sub.plan.kind != "free" and !Customers.paying?(@sub)}
            id="action-free"
            size="sm"
            phx-click="open"
            phx-value-action="free"
          >
            Move to Free
          </.button>
          <.button
            :if={!@customer.suspended_at}
            id="action-suspend"
            size="sm"
            variant="danger"
            phx-click="open"
            phx-value-action="suspend"
          >
            Suspend
          </.button>
          <.button
            :if={@customer.suspended_at}
            id="action-unsuspend"
            size="sm"
            variant="primary"
            phx-click="open"
            phx-value-action="unsuspend"
          >
            Unsuspend
          </.button>
        </div>
      </header>

      <p
        :if={@customer.suspended_at}
        id="suspension-note"
        class="mb-6 rounded-field bg-ks-amber-soft p-4 text-sm text-ks-amber-deep"
      >
        Suspended on {date(@customer.suspended_at)}: {@customer.suspension_reason}. They can't sign in,
        their shared links don't open and renewals are paused.
      </p>

      <div class="grid gap-4 lg:grid-cols-2">
        <.card id="customer-plan" title="Plan">
          <dl class="flex flex-col gap-2 text-[15px]">
            <.row label="Plan">{Billing.status_label(@sub)}</.row>
            <.row :if={@sub.complimentary} label="Given by staff">
              Until {date(@sub.current_period_end)}
            </.row>
            <.row :if={@sub.status == "trialing"} label="Trial ends">{date(@sub.trial_ends_at)}</.row>
            <.row :if={@sub.grace_ends_at && @sub.status == "grace"} label="Grace ends">
              {date(@sub.grace_ends_at)}
            </.row>
            <.row :if={@sub.price} label="Price">
              {Price.format(@sub.price)} / {@sub.price.interval}
            </.row>
            <.row
              :if={@sub.current_period_end && !@sub.complimentary}
              label={if(@sub.cancel_at_period_end, do: "Ends on", else: "Renews on")}
            >
              {date(@sub.current_period_end)}
            </.row>
            <.row :if={@profile.payment_method} label="Card">
              {PaymentMethod.label(@profile.payment_method)}
            </.row>
            <.row label="Free months banked">{@customer.free_months_banked}</.row>
            <.row :if={@sub.discount_redemption} label="Discount">
              {@sub.discount_redemption.discount_code.code}
            </.row>
          </dl>
          <details :if={@profile.events != []} class="mt-1">
            <summary class="cursor-pointer text-sm text-primary">Plan history</summary>
            <ol id="plan-history" class="mt-2 flex flex-col gap-1.5 text-sm">
              <li :for={e <- @profile.events} class="flex justify-between gap-3">
                <span>
                  {humanize(e.kind)}<span
                    :if={e.to_plan && e.to_plan != e.from_plan}
                    class="text-ks-muted"
                  > · {e.from_plan || "—"} → {e.to_plan}</span>
                </span>
                <span class="shrink-0 font-mono text-xs text-ks-muted">{date(e.inserted_at)}</span>
              </li>
            </ol>
          </details>
        </.card>

        <.card id="customer-usage" title="Usage">
          <dl class="flex flex-col gap-2 text-[15px]">
            <.row label="Albums">
              {length(@profile.albums)} of {limit(@profile.limits.max_albums)}
            </.row>
            <.row label="Photos">{@profile.photos}</.row>
            <.row label="Storage">
              {Keepsakes.Format.bytes(@profile.storage_used)} of {limit_bytes(
                @profile.limits.storage_bytes
              )}
            </.row>
          </dl>
          <p
            :if={@over_limit != []}
            id="over-limit"
            class="rounded-field bg-ks-amber-soft p-3 text-sm text-ks-amber-deep"
          >
            Over the plan's {Enum.join(@over_limit, " and ")}: they can't add more until they upgrade or make room.
          </p>
        </.card>

        <.card id="customer-albums" title="Albums">
          <p :if={@profile.albums == []} class="text-sm text-ks-muted">No albums yet.</p>
          <ul :if={@profile.albums != []} class="flex flex-col divide-y divide-base-300">
            <li :for={album <- @profile.albums} class="flex items-center justify-between gap-3 py-2">
              <span class="min-w-0">
                <span class="block truncate font-medium">{album.name}</span>
                <span class="text-sm text-ks-muted">
                  {album.memories_count} photos · created {date(album.inserted_at)}
                </span>
              </span>
              <.badge :if={MapSet.member?(@profile.shared_album_ids, album.id)} variant="ready">
                Shared
              </.badge>
            </li>
          </ul>
        </.card>

        <.card id="customer-tickets" title="Support tickets">
          <p :if={@profile.tickets == []} class="text-sm text-ks-muted">No tickets.</p>
          <ul :if={@profile.tickets != []} class="flex flex-col divide-y divide-base-300">
            <li :for={t <- @profile.tickets} class="flex items-center justify-between gap-3 py-2">
              <span class="min-w-0">
                <span class="block truncate font-medium">{t.subject}</span>
                <span class="font-mono text-xs text-ks-muted">{t.number} · {date(t.inserted_at)}</span>
              </span>
              <.status_badge status={t.status} />
            </li>
          </ul>
        </.card>

        <.card :if={@profile.invoices} id="customer-invoices" title="Invoices">
          <p :if={@profile.invoices == []} class="text-sm text-ks-muted">No invoices.</p>
          <ul :if={@profile.invoices != []} class="flex flex-col divide-y divide-base-300">
            <li
              :for={i <- @profile.invoices}
              class="flex items-center justify-between gap-3 py-2 text-[15px]"
            >
              <.link
                navigate={~p"/finance/invoices/#{i.id}"}
                class="font-mono text-sm font-bold text-primary"
              >
                {i.number}
              </.link>
              <span class="tabular-nums">{Price.format(i.currency, i.amount_minor)}</span>
              <.badge variant={if(i.status == "paid", do: "ready", else: "muted")}>{i.status}</.badge>
              <span class="font-mono text-xs text-ks-muted">{date(i.inserted_at)}</span>
            </li>
          </ul>
        </.card>

        <.card :if={@profile.activity} id="customer-activity" title="Staff activity">
          <p :if={@profile.activity == []} class="text-sm text-ks-muted">No staff changes yet.</p>
          <ul :if={@profile.activity != []} class="flex flex-col gap-2 text-sm">
            <li :for={e <- @profile.activity} class="flex justify-between gap-3">
              <span>
                <span class="font-mono text-[13px] font-bold">{e.action}</span>
                <span class="text-ks-muted"> by {e.actor_email}</span>
              </span>
              <span class="shrink-0 font-mono text-xs text-ks-muted">{date(e.inserted_at)}</span>
            </li>
          </ul>
        </.card>
      </div>

      <.modal
        :if={@action}
        id="customer-dialog"
        show
        title={action_title(@action)}
        subtitle={action_subtitle(@action, @customer)}
        on_cancel={JS.push("close")}
      >
        <.form for={@form} id="customer-action-form" phx-submit="save" class="flex flex-col gap-2">
          <%= case @action do %>
            <% "extend" -> %>
              <.input
                field={@form[:days]}
                type="number"
                label="Days to add"
                min="1"
                max="90"
                required
              />
            <% "gift" -> %>
              <.input
                field={@form[:months]}
                type="number"
                label="Free months"
                min="1"
                max="12"
                required
              />
              <.input
                field={@form[:reason]}
                label="Reason (for the audit log)"
                maxlength="200"
                required
              />
            <% "give" -> %>
              <.input
                field={@form[:plan]}
                type="select"
                label="Plan"
                options={Customers.giftable_plans()}
              />
              <.input
                field={@form[:until]}
                type="date"
                label="Until"
                min={Date.to_iso8601(Date.utc_today())}
                required
              />
            <% "suspend" -> %>
              <.input
                field={@form[:reason]}
                type="textarea"
                label="Reason (staff only; the customer isn't emailed)"
                rows="2"
                maxlength="200"
                required
              />
            <% _ -> %>
          <% end %>
          <p :if={@error} id="customer-action-error" class="text-sm text-error">{@error}</p>
          <div class="flex justify-end gap-2.5 pt-1">
            <.button type="button" phx-click={JS.exec("data-cancel", to: "#customer-dialog")}>
              Cancel
            </.button>
            <.button
              id="customer-action-save"
              variant={if(@action == "suspend", do: "danger", else: "primary")}
              phx-disable-with="Saving…"
            >
              {action_button(@action)}
            </.button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp card(assigns) do
    ~H"""
    <section id={@id} class="flex flex-col gap-3 rounded-box border border-base-300 bg-base-100 p-5">
      <h2 class="font-bold">{@title}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp row(assigns) do
    ~H"""
    <div class="flex justify-between gap-3">
      <dt class="text-ks-muted">{@label}</dt>
      <dd class="text-right font-medium">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    customer = Customers.get!(socket.assigns.staff_scope, id)

    {:ok,
     socket
     |> assign(
       page_title: User.full_name(customer),
       manage?: StaffScope.can?(socket.assigns.staff_scope, "users.manage"),
       action: nil,
       form: nil,
       error: nil
     )
     |> load(customer)}
  end

  @impl true
  def handle_event("open", %{"action" => action}, socket) do
    defaults = %{
      "days" => "14",
      "months" => "1",
      "reason" => "",
      "plan" => "",
      "until" => Date.utc_today() |> Date.add(30) |> Date.to_iso8601()
    }

    {:noreply, assign(socket, action: action, form: to_form(defaults, as: :action), error: nil)}
  end

  def handle_event("close", _params, socket),
    do: {:noreply, assign(socket, action: nil, error: nil)}

  def handle_event("save", params, socket) do
    params = params["action"] || %{}
    %{staff_scope: scope, customer: customer, action: action} = socket.assigns

    result =
      case action do
        "extend" ->
          Customers.extend_trial(scope, customer, int(params["days"]))

        "gift" ->
          Customers.gift_months(scope, customer, int(params["months"]), params["reason"])

        "give" ->
          Customers.give_plan(scope, customer, params["plan"], date_param(params["until"]))

        "free" ->
          Customers.move_to_free(scope, customer)

        "suspend" ->
          Customers.suspend(scope, customer, params["reason"])

        "unsuspend" ->
          Customers.unsuspend(scope, customer)
      end

    case result do
      {:ok, _user, tokens} ->
        KeepsakesWeb.UserAuth.disconnect_sessions(tokens)
        {:noreply, done(socket, action)}

      {:ok, _} ->
        {:noreply, done(socket, action)}

      {:error, reason} ->
        {:noreply, assign(socket, error: error_text(reason), form: to_form(params, as: :action))}
    end
  end

  defp done(socket, action) do
    customer = Customers.get!(socket.assigns.staff_scope, socket.assigns.customer.id)

    socket
    |> assign(action: nil, error: nil)
    |> load(customer)
    |> put_flash(:info, done_text(action))
  end

  defp load(socket, customer) do
    profile = Customers.profile(socket.assigns.staff_scope, customer)
    limits = profile.limits

    over_limit =
      [
        {"storage", profile.storage_used, limits.storage_bytes},
        {"album limit", length(profile.albums), limits.max_albums}
      ]
      |> Enum.filter(fn {_name, used, max} -> max != :unlimited and used > max end)
      |> Enum.map(&elem(&1, 0))

    assign(socket,
      customer: customer,
      profile: profile,
      sub: profile.subscription,
      over_limit: over_limit
    )
  end

  defp int(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp date_param(value) do
    case Date.from_iso8601(to_string(value)) do
      {:ok, date} -> date
      _ -> Date.utc_today()
    end
  end

  defp action_title("extend"), do: "Extend the free trial"
  defp action_title("gift"), do: "Gift free months"
  defp action_title("give"), do: "Give a plan"
  defp action_title("free"), do: "Move to Free"
  defp action_title("suspend"), do: "Suspend this account"
  defp action_title("unsuspend"), do: "Unsuspend this account"

  defp action_subtitle("extend", _c), do: "They're emailed the new end date."
  defp action_subtitle("gift", _c), do: "Used on their next paid checkout, like referral months."

  defp action_subtitle("give", _c),
    do: "Free of charge until the date, then they move to Free. They're emailed."

  defp action_subtitle("free", _c),
    do: "Their trial or given plan ends now. Nothing they've added is deleted."

  defp action_subtitle("suspend", _c),
    do: "They're signed out and can't sign in, their shared links stop and renewals pause."

  defp action_subtitle("unsuspend", c),
    do: "Suspended for: #{c.suspension_reason}. They can sign in again and their links work."

  defp action_button("suspend"), do: "Suspend"
  defp action_button("unsuspend"), do: "Unsuspend"
  defp action_button("free"), do: "Move to Free"
  defp action_button(_action), do: "Save"

  defp done_text("extend"), do: "Trial extended."
  defp done_text("gift"), do: "Free months added."
  defp done_text("give"), do: "Plan given."
  defp done_text("free"), do: "Moved to the Free plan."
  defp done_text("suspend"), do: "Account suspended."
  defp done_text("unsuspend"), do: "Account unsuspended."

  defp error_text(:invalid), do: "Check the numbers: that's outside what's allowed."
  defp error_text(:invalid_date), do: "Pick a date in the future, at most two years away."
  defp error_text(:not_on_trial), do: "They're not on the free trial any more."
  defp error_text(:paying), do: "They're paying for a plan; that can't be changed here."
  defp error_text(:already_free), do: "They're already on the Free plan."
  defp error_text(:reason_required), do: "Add a reason."
  defp error_text(:already_suspended), do: "This account is already suspended."
  defp error_text(:not_suspended), do: "This account isn't suspended."
  defp error_text(:staff), do: "Staff accounts can't be suspended here."

  defp limit(:unlimited), do: "unlimited"
  defp limit(n), do: n

  defp limit_bytes(:unlimited), do: "unlimited"
  defp limit_bytes(n), do: Keepsakes.Format.bytes(n)

  defp humanize(kind), do: kind |> String.replace("_", " ") |> String.capitalize()

  defp date(nil), do: "—"
  defp date(at), do: Calendar.strftime(at, "%-d %b %Y")
end
