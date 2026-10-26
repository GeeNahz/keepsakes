defmodule KeepsakesWeb.BillingController do
  @moduledoc """
  `GET /billing/return`: where Flutterwave sends the customer after the
  card page, with `status`, `tx_ref` and (on success) `transaction_id`.
  The query string is only a hint: the payment is confirmed with
  Flutterwave before anything changes.
  """
  use KeepsakesWeb, :controller

  alias Keepsakes.Billing
  alias Keepsakes.Billing.Payment
  alias Keepsakes.Repo

  def return(conn, %{"tx_ref" => tx_ref} = params) do
    %{user: user} = conn.assigns.current_scope

    payment = Repo.get_by(Payment, tx_ref: tx_ref, user_id: user.id)

    cond do
      is_nil(payment) ->
        conn |> put_flash(:error, "We couldn't find that payment.") |> redirect(to: ~p"/billing")

      params["status"] == "cancelled" ->
        Billing.abandon(tx_ref)

        conn
        |> put_flash(:info, "Payment cancelled. You haven't been charged.")
        |> redirect(to: ~p"/billing")

      true ->
        result = Billing.confirm(tx_ref, params["transaction_id"])

        conn
        |> put_flash(flash_kind(result), message(result))
        |> redirect(to: ~p"/billing")
    end
  end

  def return(conn, _params), do: redirect(conn, to: ~p"/billing")

  defp flash_kind({:ok, _}), do: :info
  defp flash_kind(_), do: :error

  defp message({:ok, :paid}), do: "Payment received. Thank you! Your receipt is on its way."

  defp message({:ok, :pending}),
    do: "We're confirming your payment with the bank. This page will update once it's through."

  defp message({:error, :failed}), do: "The payment didn't go through. You haven't been charged."

  defp message({:error, :mismatch}),
    do:
      "Something didn't add up with that payment, so we didn't apply it. Please contact support."

  defp message({:error, _}),
    do: "We couldn't reach the payment provider to confirm. We'll keep checking."
end
