defmodule Keepsakes.MetricsTest do
  use Keepsakes.DataCase, async: true

  import Keepsakes.AccountsFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.Metrics

  test "customer figures leave staff out" do
    scope = staff_scope_fixture()
    user_fixture()
    user_fixture()

    metrics = Metrics.dashboard(scope)
    assert metrics.customers == 2
    assert metrics.new_7d == 2
    assert metrics.trials == 2
    assert metrics.paying == 0
    assert metrics.churn_rate == nil
    assert metrics.mrr == %{}
  end

  test "daily series cover 30 days, today last" do
    scope = staff_scope_fixture()
    user_fixture()

    %{signups_per_day: days, uploads_per_day: uploads} = Metrics.dashboard(scope)
    assert length(days) == 30
    assert List.last(days) == {Date.utc_today(), 1}
    assert Enum.all?(uploads, fn {_date, n} -> n == 0 end)
  end

  test "needs dashboard.view" do
    {:ok, role} =
      Keepsakes.Staff.create_role(staff_scope_fixture(), %{
        "name" => "Auditors",
        "permissions" => ["audit.view"]
      })

    assert_raise Keepsakes.Staff.Forbidden, fn ->
      Metrics.dashboard(staff_scope_fixture([role.key]))
    end
  end
end
