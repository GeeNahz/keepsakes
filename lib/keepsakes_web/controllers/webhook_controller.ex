defmodule KeepsakesWeb.WebhookController do
  @moduledoc """
  `POST /webhooks/flutterwave`. Answers fast: the event is checked
  (`verif-hash`), stored once and handed to a background job; the payment
  itself is only trusted after the job re-verifies it with Flutterwave.
  """
  use KeepsakesWeb, :controller

  alias Keepsakes.Billing.Payments

  def flutterwave(conn, params) do
    case Payments.receive_webhook(conn.req_headers, params) do
      :ok -> send_resp(conn, 200, "ok")
      {:error, :invalid} -> send_resp(conn, 401, "invalid signature")
    end
  end
end
