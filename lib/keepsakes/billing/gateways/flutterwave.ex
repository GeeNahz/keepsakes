defmodule Keepsakes.Billing.Gateways.Flutterwave do
  @moduledoc """
  Flutterwave v3 over `Req`.

    * checkout: `POST /payments` (Flutterwave Standard, card only); the
      customer comes back to our `redirect_url` with `tx_ref` and
      `transaction_id`
    * `GET /transactions/:id/verify` and
      `GET /transactions/verify_by_reference?tx_ref=` - the only source of
      truth; redirects and webhooks just tell us when to look
    * `POST /tokenized-charges` - renewals with the card token from the
      first payment (`data.card.token`)
    * webhooks carry our secret hash in `verif-hash`

  Amounts are major units at Flutterwave (5000.0 NGN); ours are minor
  (500_000 kobo).

  Config (`config/runtime.exs`): `:secret_key`, `:secret_hash`, and
  `:req_options` in tests (`Req.Test`).
  """
  @behaviour Keepsakes.Billing.Gateway

  alias Keepsakes.Billing.Charge

  @base_url "https://api.flutterwave.com/v3"

  @impl true
  def name, do: "flutterwave"

  @impl true
  def init_checkout(checkout) do
    body = %{
      tx_ref: checkout.tx_ref,
      amount: to_major(checkout.amount_minor),
      currency: checkout.currency,
      redirect_url: checkout.redirect_url,
      payment_options: "card",
      customer: %{email: checkout.email, name: checkout.name},
      customizations: %{title: checkout.title, description: checkout.description}
    }

    case request(:post, "/payments", json: body) do
      {:ok, %{"status" => "success", "data" => %{"link" => link}}} -> {:ok, %{link: link}}
      {:ok, body} -> {:error, {:rejected, body["message"]}}
      error -> error
    end
  end

  @impl true
  def verify(gateway_id) do
    case request(:get, "/transactions/#{URI.encode(to_string(gateway_id))}/verify") do
      {:ok, %{"status" => "success", "data" => data}} -> {:ok, to_charge(data)}
      {:ok, body} -> {:error, {:rejected, body["message"]}}
      error -> error
    end
  end

  @impl true
  def verify_by_reference(tx_ref) do
    case request(:get, "/transactions/verify_by_reference", params: [tx_ref: tx_ref]) do
      {:ok, %{"status" => "success", "data" => data}} -> {:ok, to_charge(data)}
      {:error, {:http, 404, _}} -> {:error, :not_found}
      {:ok, %{"status" => "error"}} -> {:error, :not_found}
      error -> error
    end
  end

  @impl true
  def charge_token(charge) do
    body = %{
      token: charge.token,
      email: charge.email,
      amount: to_major(charge.amount_minor),
      currency: charge.currency,
      tx_ref: charge.tx_ref,
      narration: "Keepsake subscription"
    }

    case request(:post, "/tokenized-charges", json: body) do
      {:ok, %{"status" => "success", "data" => data}} ->
        {:ok, to_charge(data)}

      # A declined card is an answer, not an outage
      {:ok, %{"status" => "error"} = body} ->
        {:ok,
         %Charge{tx_ref: charge.tx_ref, status: :failed, message: body["message"], raw: body}}

      {:error, {:http, status, body}} when status in 400..499 ->
        {:ok,
         %Charge{
           tx_ref: charge.tx_ref,
           status: :failed,
           message: is_map(body) && body["message"],
           raw: if(is_map(body), do: body, else: %{})
         }}

      error ->
        error
    end
  end

  @impl true
  def refund(gateway_id, amount_minor) do
    case request(:post, "/transactions/#{URI.encode(to_string(gateway_id))}/refund",
           json: %{amount: to_major(amount_minor)}
         ) do
      {:ok, %{"status" => "success"}} -> :ok
      {:ok, body} -> {:error, {:rejected, body["message"]}}
      error -> error
    end
  end

  @impl true
  def valid_webhook?(headers) do
    expected = config()[:secret_hash]

    case List.keyfind(headers, "verif-hash", 0) do
      {_, given} when is_binary(expected) and expected != "" ->
        Plug.Crypto.secure_compare(given, expected)

      _ ->
        false
    end
  end

  @impl true
  def parse_webhook(%{"event" => "charge.completed" = type, "data" => %{"id" => id} = data}) do
    {:ok, %{id: "#{type}:#{id}", type: type, gateway_id: to_string(id), tx_ref: data["tx_ref"]}}
  end

  def parse_webhook(_body), do: :ignore

  ## Helpers

  defp request(method, path, options \\ []) do
    secret = config()[:secret_key] || raise "FLW_SECRET_KEY is not set"

    [
      method: method,
      url: @base_url <> path,
      auth: {:bearer, secret},
      receive_timeout: 30_000,
      retry: :transient
    ]
    |> Keyword.merge(config()[:req_options] || [])
    |> Keyword.merge(options)
    |> Req.request()
    |> case do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp to_charge(data) do
    %Charge{
      gateway_id: data["id"] && to_string(data["id"]),
      tx_ref: data["tx_ref"],
      status: status(data["status"]),
      amount_minor: to_minor(data["amount"]),
      currency: data["currency"],
      card: card(data),
      message: data["processor_response"],
      raw: data
    }
  end

  defp status("successful"), do: :successful
  defp status(status) when status in ["pending", "processing", "new"], do: :pending
  defp status(_), do: :failed

  defp card(%{"card" => %{"token" => token} = card} = data) when is_binary(token) do
    %{
      token: token,
      brand: card["type"],
      last4: card["last_4digits"],
      expiry: card["expiry"],
      email: get_in(data, ["customer", "email"])
    }
  end

  defp card(_data), do: nil

  defp to_major(minor), do: minor / 100
  defp to_minor(nil), do: nil
  defp to_minor(major), do: round(major * 100)

  defp config, do: Application.get_env(:keepsakes, __MODULE__, [])
end
