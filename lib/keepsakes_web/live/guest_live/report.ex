defmodule KeepsakesWeb.GuestLive.Report do
  @moduledoc """
  `/a/:slug/report`: anyone with an album's link can report it (a reason,
  details and an optional email to reply to). Creates a high-priority
  abuse ticket for staff. 5 reports per hour per address.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.{RateLimit, Support}
  alias KeepsakesWeb.AuthThrottle

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:guest}>
      <main class="flex min-h-screen items-start justify-center px-4 py-12 md:items-center">
        <div class="flex w-full max-w-[520px] flex-col gap-6">
          <%= cond do %>
            <% is_nil(@link) -> %>
              <div id="report-unavailable" class="flex flex-col gap-3 text-center">
                <h1 class="text-[28px] font-bold">This link isn't available</h1>
                <p class="text-ks-guest-text">There's nothing to report here any more.</p>
              </div>
            <% @sent -> %>
              <div id="report-sent" class="flex flex-col items-center gap-3 text-center">
                <.icon name="hero-shield-check" class="size-12 text-primary" />
                <h1 class="text-[28px] font-bold">Thanks for telling us</h1>
                <p class="text-ks-guest-text">
                  We'll review the album. If you left an email, we'll reply there.
                </p>
              </div>
            <% true -> %>
              <div class="flex flex-col gap-2">
                <h1 class="text-[32px] font-bold leading-tight">Report this album</h1>
                <p class="text-ks-guest-text">
                  Tell us if “{@album.name}” shows something it shouldn't. Reports go to the Keepsake team, not the album's owner.
                </p>
              </div>
              <form id="report-form" phx-submit="send" class="flex flex-col gap-4">
                <fieldset class="flex flex-col gap-2">
                  <legend class="pb-2 text-sm font-bold">What's wrong?</legend>
                  <label
                    :for={reason <- Support.report_reasons()}
                    class="flex cursor-pointer items-center gap-3 rounded-xl border border-ks-guest-line bg-ks-guest-field px-4 py-3 has-checked:border-primary"
                  >
                    <input
                      type="radio"
                      name="reason"
                      value={reason}
                      required
                      class="radio radio-primary radio-sm"
                    />
                    <span>{reason}</span>
                  </label>
                </fieldset>
                <label class="flex flex-col gap-1.5">
                  <span class="text-sm font-bold">Details
                  <span class="font-normal text-ks-guest-text">(optional)</span></span>
                  <textarea
                    id="report-details"
                    name="details"
                    rows="3"
                    maxlength="3000"
                    placeholder="Which photo, and anything else that helps us check."
                    class="textarea w-full border-ks-guest-edge bg-ks-guest-field text-ks-guest-ink"
                  ></textarea>
                </label>
                <label class="flex flex-col gap-1.5">
                  <span class="text-sm font-bold">Your email
                  <span class="font-normal text-ks-guest-text">(optional, to hear back)</span></span>
                  <input
                    id="report-email"
                    name="email"
                    type="email"
                    maxlength="160"
                    class="input w-full border-ks-guest-edge bg-ks-guest-field text-ks-guest-ink"
                  />
                </label>
                <p :if={@error} id="report-error" class="text-sm text-error">{@error}</p>
                <button
                  id="send-report"
                  type="submit"
                  class="btn btn-primary h-12 rounded-xl font-bold"
                  phx-disable-with="Sending…"
                >
                  Send report
                </button>
              </form>
              <.link
                navigate={@base_path}
                class="text-center text-sm font-bold text-primary no-underline"
              >
                Back to the album
              </.link>
          <% end %>
        </div>
      </main>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Report an album",
       sent: false,
       error: nil,
       client_ip: AuthThrottle.client_ip(get_connect_info(socket, :peer_data))
     )}
  end

  @impl true
  def handle_event("send", params, socket) do
    with :ok <- RateLimit.check("report:#{socket.assigns.client_ip}", 60 * 60_000, 5),
         {:ok, _ticket} <- Support.report_album(socket.assigns.link, params) do
      {:noreply, assign(socket, sent: true)}
    else
      {:error, {:rate_limited, _} = reason} ->
        {:noreply, assign(socket, error: AuthThrottle.message(reason))}

      {:error, :invalid} ->
        {:noreply, assign(socket, error: "Please choose what's wrong.")}
    end
  end
end
