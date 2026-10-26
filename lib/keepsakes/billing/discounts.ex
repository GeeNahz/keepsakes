defmodule Keepsakes.Billing.Discounts do
  @moduledoc """
  Discount codes: creating them, checking one a customer typed, and
  working out what it takes off.

  Codes are created with `mix keepsakes.discount.create` until the admin
  portal (Stage 7); in a release:

      bin/keepsakes eval 'Keepsakes.Billing.Discounts.create_code(%{code: "LAUNCH20", percent_off: 20, duration: "repeating", duration_months: 3})'

  A code is checked when it's typed (for the price shown) and again when
  the payment is confirmed; each user can use a code once.
  """
  import Ecto.Query

  alias Keepsakes.Billing.{DiscountCode, DiscountRedemption, Plan, Price}
  alias Keepsakes.Repo

  @type problem :: :not_found | :expired | :used_up | :wrong_plan | :already_used

  @doc "Creates a code (see `DiscountCode.changeset/2` for the fields)."
  @spec create_code(map()) :: {:ok, DiscountCode.t()} | {:error, Ecto.Changeset.t()}
  def create_code(attrs), do: %DiscountCode{} |> DiscountCode.changeset(attrs) |> Repo.insert()

  @doc """
  The code `typed` if `user_id` may use it on `price` now, else the
  reason it can't be used.
  """
  @spec check(String.t(), Ecto.UUID.t(), Price.t(), DateTime.t()) ::
          {:ok, DiscountCode.t()} | {:error, problem()}
  def check(typed, user_id, %Price{} = price, now \\ DateTime.utc_now()) do
    price = Repo.preload(price, :plan)

    case Repo.get_by(DiscountCode, code: DiscountCode.normalize(typed)) do
      nil ->
        {:error, :not_found}

      code ->
        cond do
          not code.active ->
            {:error, :not_found}

          code.expires_at && not DateTime.after?(code.expires_at, now) ->
            {:error, :expired}

          code.max_redemptions && code.redemptions_count >= code.max_redemptions ->
            {:error, :used_up}

          not for_plan?(code, price.plan) ->
            {:error, :wrong_plan}

          used?(code, user_id) ->
            {:error, :already_used}

          true ->
            {:ok, code}
        end
    end
  end

  defp used?(%DiscountCode{id: id}, user_id) do
    Repo.exists?(
      from r in DiscountRedemption, where: r.discount_code_id == ^id and r.user_id == ^user_id
    )
  end

  @doc "Whether the code works for `plan` (codes without plans work for all)."
  def for_plan?(%DiscountCode{plan_slugs: []}, _plan), do: true
  def for_plan?(%DiscountCode{plan_slugs: slugs}, %Plan{slug: slug}), do: slug in slugs

  @doc "What `percent` takes off `amount_minor`, rounded down to a whole naira/dollar."
  def amount_off(amount_minor, percent), do: div(div(amount_minor * percent, 100), 100) * 100

  @doc """
  The user's discount that still applies to `plan` for a period starting
  at `period_start`, or nil.
  """
  @spec active(DiscountRedemption.t() | nil, Plan.t(), DateTime.t()) ::
          DiscountRedemption.t() | nil
  def active(nil, _plan, _period_start), do: nil

  def active(%DiscountRedemption{} = redemption, plan, period_start) do
    redemption = Repo.preload(redemption, :discount_code)

    if DiscountRedemption.applies?(redemption, period_start) and
         for_plan?(redemption.discount_code, plan),
       do: redemption
  end

  @doc """
  Records that `user_id` used `code` from `period_start` (inside the
  payment's transaction). Repeating codes run `duration_months` from then.
  """
  @spec redeem(DiscountCode.t(), Ecto.UUID.t(), DateTime.t()) :: DiscountRedemption.t()
  def redeem(%DiscountCode{} = code, user_id, period_start) do
    ends_at =
      if code.duration == "repeating",
        do: DateTime.shift(period_start, month: code.duration_months)

    {1, _} =
      from(c in DiscountCode, where: c.id == ^code.id)
      |> Repo.update_all(inc: [redemptions_count: 1])

    Repo.insert!(
      %DiscountRedemption{
        discount_code_id: code.id,
        user_id: user_id,
        percent_off: code.percent_off,
        duration: code.duration,
        ends_at: ends_at
      },
      on_conflict: {:replace, [:updated_at]},
      conflict_target: [:discount_code_id, :user_id]
    )
  end

  @doc "Ends a redemption (a `once` code after its first payment)."
  def finish(%DiscountRedemption{} = redemption, now) do
    redemption |> Ecto.Changeset.change(ended_at: now) |> Repo.update!()
  end

  @doc "`\"LAUNCH20 · 20% off\"`, for invoices and receipts."
  def label(code, percent), do: "#{code} · #{percent}% off"

  @doc "Friendly text for a problem with a typed code."
  def message(:not_found), do: "That code isn't valid."
  def message(:expired), do: "That code has expired."
  def message(:used_up), do: "That code has been used up."
  def message(:wrong_plan), do: "That code doesn't work for this plan."
  def message(:already_used), do: "You've already used that code."
  def message(:too_much), do: "That code can't be used for this payment."
  def message(:not_now), do: "Codes apply when you pay; this change doesn't need a payment."
end
