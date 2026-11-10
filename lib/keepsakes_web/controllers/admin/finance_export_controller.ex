defmodule KeepsakesWeb.Admin.FinanceExportController do
  @moduledoc """
  CSV downloads for the Finance section (`finance.export`): payments and
  refunds between `from` and `to` (ISO dates, both optional). Every export
  is written to the audit log.
  """
  use KeepsakesWeb, :controller

  alias Keepsakes.Finance

  def payments(conn, params),
    do:
      send_csv(
        conn,
        "payments",
        Finance.payments_csv(conn.assigns.staff_scope, params["from"], params["to"])
      )

  def refunds(conn, params),
    do:
      send_csv(
        conn,
        "refunds",
        Finance.refunds_csv(conn.assigns.staff_scope, params["from"], params["to"])
      )

  defp send_csv(conn, what, lines) do
    filename = "keepsake-#{what}-#{Date.utc_today()}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, lines)
  end
end
