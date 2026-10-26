defmodule Keepsakes.Billing.Gateway do
  @moduledoc """
  What Keepsake needs from a payment provider. `Keepsakes.Billing` only
  talks to this behaviour, so adding Paystack or Stripe (or moving to
  Flutterwave v4) means one new module, not changes across billing.

  The provider is `Keepsakes.Billing.Gateways.Flutterwave` for now; see
  `adapter/0`.
  """
  alias Keepsakes.Billing.Charge

  @type checkout :: %{
          tx_ref: String.t(),
          amount_minor: pos_integer(),
          currency: String.t(),
          email: String.t(),
          name: String.t(),
          redirect_url: String.t(),
          title: String.t(),
          description: String.t()
        }

  @type token_charge :: %{
          token: String.t(),
          email: String.t(),
          amount_minor: pos_integer(),
          currency: String.t(),
          tx_ref: String.t()
        }

  @doc "Short name stored on payments and webhook events, e.g. `\"flutterwave\"`."
  @callback name() :: String.t()

  @doc "Starts a hosted card checkout; returns the page to send the customer to."
  @callback init_checkout(checkout()) :: {:ok, %{link: String.t()}} | {:error, term()}

  @doc "Looks up a transaction by the provider's ID."
  @callback verify(gateway_id :: String.t()) :: {:ok, Charge.t()} | {:error, term()}

  @doc "Looks up a transaction by our reference (for payments left pending)."
  @callback verify_by_reference(tx_ref :: String.t()) ::
              {:ok, Charge.t()} | {:error, :not_found | term()}

  @doc "Charges a saved card without the customer present (renewals)."
  @callback charge_token(token_charge()) :: {:ok, Charge.t()} | {:error, term()}

  @doc "Refunds `amount_minor` of a successful transaction."
  @callback refund(gateway_id :: String.t(), amount_minor :: pos_integer()) ::
              :ok | {:error, term()}

  @doc "Whether a webhook request really came from the provider."
  @callback valid_webhook?(headers :: [{String.t(), String.t()}]) :: boolean()

  @doc """
  The event in a webhook body: `{:ok, %{id, type, gateway_id, tx_ref}}`,
  or `:ignore` for events Keepsake doesn't act on.
  """
  @callback parse_webhook(body :: map()) ::
              {:ok,
               %{id: String.t(), type: String.t(), gateway_id: String.t(), tx_ref: String.t()}}
              | :ignore

  @doc "The configured provider module."
  def adapter,
    do:
      Application.get_env(:keepsakes, __MODULE__, [])[:adapter] ||
        Keepsakes.Billing.Gateways.Flutterwave

  @doc "The provider's name as stored on payments, e.g. `\"flutterwave\"`."
  def name, do: adapter().name()
end
