defmodule Keepsakes.FlutterwaveStub do
  @moduledoc """
  Fake Flutterwave v3 API for tests (via `Req.Test`). Each call sends the
  test process `{:flutterwave, method, path, body}` so tests can assert on
  what was requested.

      FlutterwaveStub.stub(charge: :successful, token_charge: :failed)

  Options: `:charge` - status the verify endpoints report (`:successful`
  default, `:pending`, `:failed`); `:amount_minor`/`:currency` - override
  what verify reports (defaults to the payment's own); `:token_charge` -
  result of tokenized charges (`:successful` default, `:failed`,
  `:pending`); `:checkout` - `:ok` (default) or `:down`.
  """
  import ExUnit.Assertions, only: [flunk: 1]

  alias Keepsakes.Billing.{Gateways.Flutterwave, Payment}
  alias Keepsakes.Repo

  def stub(opts \\ []) do
    test = self()

    Req.Test.stub(Flutterwave, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = if raw == "", do: %{}, else: Jason.decode!(raw)
      send(test, {:flutterwave, conn.method, conn.request_path, body})
      respond(conn, conn.method, conn.request_path, body, opts)
    end)
  end

  defp respond(conn, "POST", "/v3/payments", body, opts) do
    case Keyword.get(opts, :checkout, :ok) do
      :ok ->
        Req.Test.json(conn, %{
          status: "success",
          data: %{link: "https://checkout.flutterwave.test/pay/#{body["tx_ref"]}"}
        })

      :down ->
        Plug.Conn.send_resp(conn, 503, "unavailable")
    end
  end

  defp respond(conn, "GET", "/v3/transactions/verify_by_reference", _body, opts) do
    verified(conn, conn.query_params["tx_ref"], opts)
  end

  defp respond(conn, "GET", "/v3/transactions/" <> rest, _body, opts) do
    "fw-" <> tx_ref = String.trim_trailing(rest, "/verify")
    verified(conn, tx_ref, opts)
  end

  defp respond(conn, "POST", "/v3/tokenized-charges", body, opts) do
    case Keyword.get(opts, :token_charge, :successful) do
      :failed ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{status: "error", message: "Insufficient funds", data: nil})

      status ->
        Req.Test.json(conn, %{
          status: "success",
          message: "Charge successful",
          data:
            transaction(
              body["tx_ref"],
              to_string(status),
              round(body["amount"] * 100),
              body["currency"]
            )
        })
    end
  end

  defp respond(_conn, method, path, _body, _opts),
    do: flunk("unexpected Flutterwave call #{method} #{path}")

  defp verified(conn, tx_ref, opts) do
    case Repo.get_by(Payment, tx_ref: tx_ref) do
      nil ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{status: "error", message: "No transaction"})

      payment ->
        status = opts |> Keyword.get(:charge, :successful) |> to_string()
        amount = Keyword.get(opts, :amount_minor, payment.amount_minor)
        currency = Keyword.get(opts, :currency, payment.currency)

        Req.Test.json(conn, %{
          status: "success",
          data: transaction(tx_ref, status, amount, currency)
        })
    end
  end

  @doc "A Flutterwave transaction body for `tx_ref` (gateway ID `fw-<tx_ref>`)."
  def transaction(tx_ref, status, amount_minor, currency) do
    %{
      id: "fw-" <> tx_ref,
      tx_ref: tx_ref,
      status: status,
      amount: amount_minor / 100,
      currency: currency,
      customer: %{email: "card@example.com"},
      card: %{
        token: "flw-t1nf-test-token",
        type: "VISA",
        last_4digits: "4242",
        expiry: "09/32"
      }
    }
  end

  @doc "A `charge.completed` webhook body for `tx_ref`."
  def webhook(tx_ref, status \\ "successful") do
    %{
      "event" => "charge.completed",
      "data" => %{"id" => "fw-" <> tx_ref, "tx_ref" => tx_ref, "status" => status}
    }
  end
end
