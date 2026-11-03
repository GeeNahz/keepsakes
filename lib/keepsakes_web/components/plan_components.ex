defmodule KeepsakesWeb.PlanComponents do
  @moduledoc """
  Plan pieces shared by the public pricing section (`KeepsakesWeb.HomeLive`)
  and the owner's billing page (`KeepsakesWeb.BillingLive.Index`), so both
  describe plans in the same words: the NGN/USD and monthly/yearly
  switches, and each plan's feature list.
  """
  use KeepsakesWeb, :html

  alias Keepsakes.Billing.{Features, Price}
  alias Keepsakes.Format

  # The features compared between plans, in order. Every one is live.
  @compared ~w(max_albums max_memories_per_album storage_bytes max_upload_mb
               collaborator_seats premium_templates guest_downloads guest_uploads
               reactions_guestbook slideshow_music time_capsule custom_domains
               remove_branding)a

  @doc "The catalogue entries (`Keepsakes.Billing.Features.all/0`) compared between plans."
  def compared, do: Enum.filter(Features.all(), &(&1.key in @compared))

  @doc "`%{key, text, on?}` per compared feature of `plan`."
  def feature_rows(plan, compared \\ compared()) do
    for feature <- compared do
      value = Features.value(plan.features, feature.key)
      %{key: feature.key, text: feature_text(feature, value), on?: value not in [false, 0]}
    end
  end

  @doc "How a feature's value reads on a plan card."
  def feature_text(%{key: :max_albums}, :unlimited), do: "Unlimited albums"
  def feature_text(%{key: :max_albums}, 1), do: "1 album"
  def feature_text(%{key: :max_albums}, count), do: "#{count} albums"
  def feature_text(%{key: :max_memories_per_album}, :unlimited), do: "Unlimited photos per album"
  def feature_text(%{key: :max_memories_per_album}, count), do: "#{count} photos per album"
  def feature_text(%{key: :storage_bytes}, :unlimited), do: "Unlimited storage"
  def feature_text(%{key: :storage_bytes}, bytes), do: "#{Format.bytes(bytes)} of storage"
  def feature_text(%{key: :max_upload_mb}, mb), do: "Photos up to #{mb} MB each"
  def feature_text(%{key: :collaborator_seats}, :unlimited), do: "Unlimited collaborators"
  def feature_text(%{key: :collaborator_seats}, 0), do: "Collaborators"
  def feature_text(%{key: :collaborator_seats}, 1), do: "1 collaborator"
  def feature_text(%{key: :collaborator_seats}, count), do: "#{count} collaborators"
  def feature_text(%{key: :custom_domains}, 0), do: "Your own domain"
  def feature_text(%{key: :custom_domains}, 1), do: "Your own domain"
  def feature_text(%{key: :custom_domains}, :unlimited), do: "Unlimited own domains"
  def feature_text(%{key: :custom_domains}, count), do: "#{count} own domains"
  def feature_text(%{name: name}, _value), do: name

  @doc """
  What a year costs against twelve months, as `{saving_minor, percent}`, or
  nil when there's no saving (or either price is missing).
  """
  def yearly_saving(%Price{amount_minor: year, currency: c}, %Price{
        amount_minor: month,
        currency: c
      })
      when month * 12 > year do
    saving = month * 12 - year
    {saving, round(saving * 100 / (month * 12))}
  end

  def yearly_saving(_year, _month), do: nil

  @doc "A plan's compared features as a checklist."
  attr :plan, :map, required: true
  attr :compared, :list, default: nil

  def feature_list(assigns) do
    assigns = assign(assigns, :rows, feature_rows(assigns.plan, assigns.compared || compared()))

    ~H"""
    <ul class="flex flex-col gap-2.5 text-sm">
      <li :for={row <- @rows} id={"plan-#{@plan.slug}-#{row.key}"} class="flex items-start gap-2">
        <.icon
          name={if row.on?, do: "hero-check", else: "hero-minus"}
          class={["mt-0.5 size-4 shrink-0", if(row.on?, do: "text-primary", else: "text-ks-field")]}
        />
        <span class={!row.on? && "text-ks-muted"}>{row.text}</span>
      </li>
    </ul>
    """
  end

  @doc "A pill switch (NGN/USD, monthly/yearly) sending `event` with `to`."
  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :value, :string, required: true
  attr :options, :list, required: true

  def segmented(assigns) do
    ~H"""
    <div
      id={@id}
      role="group"
      class="flex gap-0.5 rounded-full border border-base-300 bg-base-100 p-1"
    >
      <button
        :for={{value, label} <- @options}
        type="button"
        phx-click={@event}
        phx-value-to={value}
        aria-pressed={to_string(value == @value)}
        class="min-h-9 cursor-pointer rounded-full px-3.5 text-sm font-bold text-ks-muted transition-colors aria-pressed:bg-primary aria-pressed:text-primary-content"
      >
        {label}
      </button>
    </div>
    """
  end
end
