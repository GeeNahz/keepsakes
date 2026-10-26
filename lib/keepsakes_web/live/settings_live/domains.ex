defmodule KeepsakesWeb.SettingsLive.Domains do
  @moduledoc "`/app/settings/domains`: placeholder until custom domains arrive (Stage 8)."
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.SettingsComponents

  @impl true
  def render(assigns) do
    ~H"""
    <.settings_shell
      flash={@flash}
      current_scope={@current_scope}
      owner={@owner}
      tab={:domains}
      title="Domains"
      subtitle="Show your albums on your own web address."
    >
      <.settings_card id="domains-soon" title="Your own domain">
        <div class="flex flex-col items-start gap-3">
          <.badge variant="muted">Coming soon</.badge>
          <p class="text-[15px] leading-relaxed text-ks-muted">
            Soon you'll be able to open your albums at an address like <span class="font-mono text-base-content">memories.yourfamily.com</span>, with the same access codes.
            Custom domains will come with the Pro plan.
          </p>
        </div>
      </.settings_card>
    </.settings_shell>
    """
  end

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, page_title: "Domains")}
end
