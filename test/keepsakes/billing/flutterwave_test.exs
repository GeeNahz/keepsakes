defmodule Keepsakes.Billing.Gateways.FlutterwaveTest do
  use ExUnit.Case, async: true

  alias Keepsakes.Billing.Charge
  alias Keepsakes.Billing.Gateways.Flutterwave

  test "init_checkout sends a card-only Standard payment in major units" do
    Req.Test.stub(Flutterwave, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(raw)
      assert conn.request_path == "/v3/payments"
      assert ["Bearer FLWSECK_TEST-secret"] = Plug.Conn.get_req_header(conn, "authorization")
      assert %{"amount" => 5000.0, "currency" => "NGN", "payment_options" => "card"} = body
      assert body["customer"]["email"] == "ada@example.com"
      Req.Test.json(conn, %{status: "success", data: %{link: "https://checkout.test/x"}})
    end)

    assert {:ok, %{link: "https://checkout.test/x"}} =
             Flutterwave.init_checkout(%{
               tx_ref: "ks-1",
               amount_minor: 500_000,
               currency: "NGN",
               email: "ada@example.com",
               name: "Ada",
               redirect_url: "http://localhost/app/billing/return",
               title: "Keepsake",
               description: "Plus · monthly"
             })
  end

  test "verify maps the transaction and card token" do
    Req.Test.stub(Flutterwave, fn conn ->
      assert conn.request_path == "/v3/transactions/123/verify"

      Req.Test.json(conn, %{
        status: "success",
        data: %{
          id: 123,
          tx_ref: "ks-1",
          status: "successful",
          amount: 5000,
          currency: "NGN",
          customer: %{email: "ada@example.com"},
          card: %{token: "tok", type: "MASTERCARD", last_4digits: "1234", expiry: "01/30"}
        }
      })
    end)

    assert {:ok,
            %Charge{
              gateway_id: "123",
              status: :successful,
              amount_minor: 500_000,
              card: %{token: "tok", last4: "1234", brand: "MASTERCARD", email: "ada@example.com"}
            }} = Flutterwave.verify("123")
  end

  test "a declined token charge is a failed charge, not an error" do
    Req.Test.stub(Flutterwave, fn conn ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{status: "error", message: "Insufficient funds", data: nil})
    end)

    assert {:ok, %Charge{status: :failed, message: "Insufficient funds"}} =
             Flutterwave.charge_token(%{
               token: "tok",
               email: "a@b.c",
               amount_minor: 500,
               currency: "USD",
               tx_ref: "ks-2"
             })
  end

  test "webhooks need the secret hash" do
    assert Flutterwave.valid_webhook?([{"verif-hash", "test-webhook-hash"}])
    refute Flutterwave.valid_webhook?([{"verif-hash", "nope"}])
    refute Flutterwave.valid_webhook?([])

    assert {:ok, %{id: "charge.completed:9", gateway_id: "9", tx_ref: "ks-3"}} =
             Flutterwave.parse_webhook(%{
               "event" => "charge.completed",
               "data" => %{"id" => 9, "tx_ref" => "ks-3"}
             })

    assert :ignore = Flutterwave.parse_webhook(%{"event" => "transfer.completed"})
  end
end
