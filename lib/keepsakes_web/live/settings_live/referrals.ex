defmodule KeepsakesWeb.SettingsLive.Referrals do
  @moduledoc "`/app/settings/referrals`: the invite link and the free months it has earned."
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.SettingsComponents

  alias Keepsakes.Billing

  @impl true
  def render(assigns) do
    ~H"""
    <.settings_shell
      flash={@flash}
      current_scope={@current_scope}
      owner={@owner}
      tab={:referrals}
      title="Referrals"
      subtitle="Invite friends, get a free month."
    >
      <.settings_card
        id="referrals"
        title="Your invite link"
        description="When someone joins with your link and chooses a plan, you get a month free: added to your plan if you're paying, or saved for your first paid period."
      >
        <div class="flex flex-wrap gap-2">
          <input
            id="referral-link"
            type="text"
            readonly
            value={url(~p"/auth/register?ref=#{@referrals.code}")}
            class="input h-11 min-w-0 flex-1 border-ks-field bg-base-200 font-mono text-sm"
          />
          <.button
            id="copy-referral"
            type="button"
            variant="secondary"
            phx-click={JS.dispatch("ks:copy", detail: %{from: "#referral-link"})}
          >
            <span data-copy-label>Copy link</span>
          </.button>
        </div>
        <dl id="referral-stats" class="grid grid-cols-3 gap-4 pt-2 text-center">
          <div class="flex flex-col gap-1 rounded-field bg-base-200 p-3">
            <dt class="text-xs text-ks-muted">Joined</dt>
            <dd class="text-2xl font-bold tabular-nums">{@referrals.joined}</dd>
          </div>
          <div class="flex flex-col gap-1 rounded-field bg-base-200 p-3">
            <dt class="text-xs text-ks-muted">Months earned</dt>
            <dd class="text-2xl font-bold tabular-nums">{@referrals.paid}</dd>
          </div>
          <div class="flex flex-col gap-1 rounded-field bg-base-200 p-3">
            <dt class="text-xs text-ks-muted">Waiting for your first plan</dt>
            <dd class="text-2xl font-bold tabular-nums">{@referrals.banked}</dd>
          </div>
        </dl>
      </.settings_card>
    </.settings_shell>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Referrals",
       referrals: Billing.referrals(socket.assigns.current_scope)
     )}
  end
end
