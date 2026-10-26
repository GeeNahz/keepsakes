defmodule Keepsakes.Billing.Admin do
  @moduledoc """
  Plans, prices and discount codes as staff change them in the admin
  portal. Every function takes the `%Keepsakes.Staff.Scope{}`, checks the
  permission (`plans.manage`, `discounts.manage`) and audits the change in
  the same transaction.

  Prices are never edited in place: a new amount deactivates the old
  `Price` and inserts a new one, so subscribers on the old price keep it
  (renewals charge `subscription.price`) while new buyers get the new one.
  Plans are hidden from new buyers (`public: false`), never deleted.
  """
  import Ecto.Query

  alias Keepsakes.Billing.{DiscountCode, Features, Invoice, Plan, Price, Subscription}
  alias Keepsakes.{Audit, Repo, Staff}
  alias Keepsakes.Staff.Scope, as: StaffScope

  @currencies ~w(NGN USD)
  @intervals ~w(month year)

  @doc "Price slots a paid plan can fill, as `[{currency, interval}]`."
  def price_slots, do: for(c <- @currencies, i <- @intervals, do: {c, i})

  ## Plans

  @doc "Every plan in pricing-page order, with active prices and how many are on it."
  def list_plans(%StaffScope{} = scope) do
    Staff.authorize!(scope, "plans.manage")

    counts =
      from(s in Subscription, group_by: s.plan_id, select: {s.plan_id, count(s.id)})
      |> Repo.all()
      |> Map.new()

    from(p in Plan, order_by: [asc: p.position, asc: p.name], preload: [prices: ^active_prices()])
    |> Repo.all()
    |> Enum.map(&{&1, Map.get(counts, &1.id, 0)})
  end

  def get_plan!(%StaffScope{} = scope, id) do
    Staff.authorize!(scope, "plans.manage")
    Repo.one!(from p in Plan, where: p.id == ^id, preload: [prices: ^active_prices()])
  end

  defp active_prices, do: from(p in Price, where: p.active, order_by: [p.currency, p.interval])

  @doc "A blank paid plan for the new-plan form."
  def new_plan, do: %Plan{kind: "paid", public: false, features: %{}, prices: []}

  @doc """
  The form's view of a plan: its fields, features as
  `%{"key" => %{"value" => text, "unlimited" => bool}}` (storage in GB)
  and prices as `%{"NGN_month" => "5000"}` (major units).
  """
  def plan_params(%Plan{} = plan) do
    %{
      "name" => plan.name,
      "slug" => plan.slug,
      "description" => plan.description,
      "position" => plan.position,
      "public" => plan.public,
      "features" => Map.new(Features.all(), &{to_string(&1.key), feature_param(plan, &1)}),
      "prices" =>
        Map.new(price_slots(), fn {c, i} = slot ->
          {slot_key(slot), plan.prices |> find_price(c, i) |> major()}
        end)
    }
  end

  defp feature_param(plan, %{key: key, kind: :limit, unit: unit}) do
    case Features.value(plan.features, key) do
      :unlimited -> %{"value" => "", "unlimited" => true}
      n -> %{"value" => to_string(from_unit(n, unit)), "unlimited" => false}
    end
  end

  defp feature_param(plan, %{key: key, kind: :boolean}),
    do: %{"value" => Features.value(plan.features, key), "unlimited" => false}

  @doc "The form key for a price slot: `\"NGN_month\"`."
  def slot_key({currency, interval}), do: currency <> "_" <> interval

  defp find_price(prices, currency, interval),
    do: Enum.find(prices, &(&1.currency == currency and &1.interval == interval))

  defp major(nil), do: ""

  defp major(%Price{amount_minor: minor}) when rem(minor, 100) == 0,
    do: to_string(div(minor, 100))

  defp major(%Price{amount_minor: minor}), do: :erlang.float_to_binary(minor / 100, decimals: 2)

  # Storage is edited in GB; everything else as stored
  defp from_unit(bytes, :bytes), do: div(bytes, 1024 * 1024 * 1024)
  defp from_unit(n, _unit), do: n

  defp to_unit(gb, :bytes), do: gb * 1024 * 1024 * 1024
  defp to_unit(n, _unit), do: n

  @doc "A changeset for the plan fields of `params`, for live validation."
  def change_plan(%Plan{} = plan, params \\ %{}) do
    case parse(plan, params) do
      {:ok, attrs, _prices} -> Plan.changeset(plan, attrs)
      {:error, changeset} -> changeset
    end
  end

  @doc """
  Creates a paid plan from the form params (fields, features, prices).
  Returns `{:ok, plan}` or `{:error, changeset}`.
  """
  def create_plan(%StaffScope{} = scope, params) do
    Staff.authorize!(scope, "plans.manage")
    plan = new_plan()

    with {:ok, attrs, prices} <- parse(plan, params) do
      Repo.transact(fn ->
        with {:ok, plan} <-
               plan |> Plan.changeset(Map.put(attrs, "kind", "paid")) |> Repo.insert() do
          plan = Repo.preload(plan, prices: active_prices())
          changed = set_prices(scope, plan, prices)

          Audit.record(scope, "plan.created", {"plan", plan.id, plan.name}, %{
            "features" => plan.features,
            "prices" => changed
          })

          {:ok, Repo.preload(plan, [prices: active_prices()], force: true)}
        end
      end)
    end
  end

  @doc """
  Saves the form params on `plan`. Free and Trial plans only take name,
  description and features. Feature changes apply to everyone on the plan.
  """
  def update_plan(%StaffScope{} = scope, %Plan{} = plan, params) do
    Staff.authorize!(scope, "plans.manage")

    with {:ok, attrs, prices} <- parse(plan, params) do
      Repo.transact(fn ->
        with {:ok, updated} <- plan |> Plan.changeset(attrs) |> Repo.update() do
          changed = if plan.kind == "paid", do: set_prices(scope, plan, prices), else: []

          changes =
            for field <- [:name, :description, :position, :public, :features],
                Map.get(plan, field) != Map.get(updated, field),
                into: %{},
                do:
                  {to_string(field),
                   %{"before" => Map.get(plan, field), "after" => Map.get(updated, field)}}

          if changes != %{} or changed != [] do
            Audit.record(
              scope,
              "plan.updated",
              {"plan", plan.id, updated.name},
              Map.put(changes, "prices", changed)
            )
          end

          {:ok, Repo.preload(updated, [prices: active_prices()], force: true)}
        end
      end)
    end
  end

  # Form params -> {:ok, plan attrs, %{slot => minor | nil}} or {:error, changeset}
  defp parse(plan, params) do
    fields =
      if plan.kind == "paid",
        do: ~w(name slug description position public),
        else: ~w(name description)

    # The slug of an existing plan never changes (links and code use it)
    fields = if plan.id, do: fields -- ["slug"], else: fields

    attrs =
      params
      |> Map.take(fields)
      |> Map.put("features", parse_features(params["features"] || %{}))

    prices = Map.new(price_slots(), &{&1, parse_amount(get_in(params, ["prices", slot_key(&1)]))})

    case Enum.filter(prices, fn {_slot, v} -> v == :error end) do
      [] ->
        {:ok, attrs, prices}

      bad ->
        changeset =
          Enum.reduce(bad, Plan.changeset(plan, attrs), fn {slot, _}, cs ->
            Ecto.Changeset.add_error(
              cs,
              :prices,
              "#{slot_key(slot)} must be an amount like 5000 or 12.50"
            )
          end)

        {:error, %{changeset | action: :validate}}
    end
  end

  defp parse_features(params) do
    Map.new(Features.all(), fn %{key: key, kind: kind, unit: unit} ->
      param = params[to_string(key)] || %{}

      value =
        case kind do
          :boolean ->
            param["value"] in [true, "true"]

          :limit ->
            if param["unlimited"] in [true, "true"] do
              nil
            else
              case Integer.parse(to_string(param["value"])) do
                {n, ""} when n >= 0 -> to_unit(n, unit)
                _ -> param["value"]
              end
            end
        end

      {to_string(key), value}
    end)
  end

  # "5000" or "12.50" (major units) -> minor; "" -> nil (no price)
  defp parse_amount(value) when value in [nil, ""], do: nil

  defp parse_amount(value) do
    case Decimal.parse(String.replace(to_string(value), ",", "")) do
      {d, ""} ->
        minor = d |> Decimal.mult(100) |> Decimal.round(0)
        if Decimal.gt?(minor, 0), do: Decimal.to_integer(minor), else: :error

      _ ->
        :error
    end
  end

  # New amounts replace the active price; an emptied slot stops being offered.
  # Returns what changed, for the audit entry.
  defp set_prices(scope, plan, prices) do
    Enum.flat_map(prices, fn {{currency, interval} = slot, amount} ->
      current = find_price(plan.prices, currency, interval)
      old = current && current.amount_minor

      if amount == old do
        []
      else
        if current,
          do: current |> Ecto.Changeset.change(active: false) |> Repo.update!()

        if amount,
          do:
            Repo.insert!(%Price{
              plan_id: plan.id,
              currency: currency,
              interval: interval,
              amount_minor: amount
            })

        Audit.record(scope, "price.changed", {"plan", plan.id, plan.name}, %{
          "price" => slot_key(slot),
          "before" => old,
          "after" => amount
        })

        [%{"price" => slot_key(slot), "before" => old, "after" => amount}]
      end
    end)
  end

  ## Discount codes

  @doc """
  Every code, newest first, as `{code, discounted}` where `discounted` is
  `%{currency => minor}` taken off paid invoices with it (first payments
  and renewals; matched on the stored label, as codes are unique).
  """
  def list_codes(%StaffScope{} = scope) do
    Staff.authorize!(scope, "discounts.manage")
    codes = Repo.all(from c in DiscountCode, order_by: [desc: c.inserted_at])

    totals =
      from(i in Invoice,
        where: i.status == "paid" and i.discount_minor > 0,
        group_by: [fragment("split_part(?, ' · ', 1)", i.discount_label), i.currency],
        select:
          {fragment("split_part(?, ' · ', 1)", i.discount_label), i.currency,
           sum(i.discount_minor)}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), fn {_code, currency, sum} -> {currency, to_int(sum)} end)

    Enum.map(codes, &{&1, Map.new(Map.get(totals, &1.code, []))})
  end

  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n), do: n

  def get_code!(%StaffScope{} = scope, id) do
    Staff.authorize!(scope, "discounts.manage")
    Repo.get!(DiscountCode, id)
  end

  @doc "Paid plans a code can be limited to, as `[{name, slug}]`."
  def code_plan_options do
    Repo.all(
      from p in Plan, where: p.kind == "paid", order_by: p.position, select: {p.name, p.slug}
    )
  end

  @doc "Changeset for the code form (date-only expiry; locked fields kept once used)."
  def change_code(%DiscountCode{} = code, params \\ %{}),
    do: DiscountCode.changeset(code, code_attrs(code, params))

  def create_code(%StaffScope{} = scope, params) do
    Staff.authorize!(scope, "discounts.manage")

    Repo.transact(fn ->
      with {:ok, code} <- %DiscountCode{} |> change_code(params) |> Repo.insert() do
        Audit.record(
          scope,
          "discount.created",
          {"discount", code.id, code.code},
          code_audit(code)
        )

        {:ok, code}
      end
    end)
  end

  def update_code(%StaffScope{} = scope, %DiscountCode{} = code, params) do
    Staff.authorize!(scope, "discounts.manage")

    Repo.transact(fn ->
      with {:ok, updated} <- code |> change_code(params) |> Repo.update() do
        Audit.record(scope, "discount.updated", {"discount", code.id, code.code}, %{
          "before" => code_audit(code),
          "after" => code_audit(updated)
        })

        {:ok, updated}
      end
    end)
  end

  @doc "Whether the code's terms are locked (someone has used it)."
  def locked?(%DiscountCode{redemptions_count: n}), do: n > 0

  # What people agreed to stays as it was once someone has used the code
  defp code_attrs(code, params) do
    params =
      if locked?(code),
        do: Map.drop(params, ~w(code percent_off duration duration_months)),
        else: params

    params
    |> Map.update("plan_slugs", [], fn slugs -> Enum.reject(List.wrap(slugs), &(&1 == "")) end)
    |> Map.update("expires_at", nil, &end_of_day/1)
    |> Map.update("max_redemptions", nil, &blank_nil/1)
  end

  defp end_of_day(value) when value in [nil, ""], do: nil

  defp end_of_day(value) do
    case Date.from_iso8601(to_string(value)) do
      {:ok, date} -> DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
      _ -> value
    end
  end

  defp blank_nil(""), do: nil
  defp blank_nil(value), do: value

  defp code_audit(code) do
    %{
      "percent_off" => code.percent_off,
      "duration" => DiscountCode.summary(code),
      "max_redemptions" => code.max_redemptions,
      "expires_at" => code.expires_at && DateTime.to_iso8601(code.expires_at),
      "plans" => code.plan_slugs,
      "active" => code.active
    }
  end
end
