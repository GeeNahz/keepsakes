defmodule Keepsakes.Billing.WebhookWorker do
  @moduledoc """
  Handles a stored payment webhook (`Keepsakes.Billing.PaymentEvent`) by
  confirming its payment with the gateway. Runs after the webhook request
  has already answered 200, so slow gateway calls never cause retries.
  """
  use Oban.Worker, queue: :billing, max_attempts: 10

  @impl true
  def perform(%Oban.Job{args: %{"payment_event_id" => id}}) do
    case Keepsakes.Billing.Payments.process_event(id) do
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  end
end
