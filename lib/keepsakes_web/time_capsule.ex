defmodule KeepsakesWeb.TimeCapsule do
  @moduledoc """
  The time capsule form: a date and time in the owner's own timezone.

  A `datetime-local` input has no timezone, so a colocated hook fills a
  hidden `offset` field with the browser's offset for the chosen moment
  (`Date#getTimezoneOffset`, minutes behind UTC); `parse/1` turns the
  pair into UTC. Times are shown back in UTC; guests' countdowns show
  local time in the browser.
  """
  use KeepsakesWeb, :html

  @max_years 50

  @doc """
  `%{"at" => "2027-05-12T09:00", "offset" => "-60"}` to `{:ok, utc}`;
  an empty `at` is `{:ok, nil}` (no capsule).
  """
  @spec parse(map()) :: {:ok, DateTime.t() | nil} | {:error, String.t()}
  def parse(%{"at" => at} = params) when at in [nil, ""] and is_map(params), do: {:ok, nil}

  def parse(%{"at" => at} = params) do
    offset =
      case Integer.parse(to_string(params["offset"] || "0")) do
        {minutes, ""} when minutes in -900..900 -> minutes
        _ -> 0
      end

    now = DateTime.utc_now()

    with {:ok, naive} <- NaiveDateTime.from_iso8601(normalise(at)),
         utc = naive |> NaiveDateTime.add(offset * 60) |> DateTime.from_naive!("Etc/UTC"),
         :gt <- DateTime.compare(utc, now),
         :lt <- DateTime.compare(utc, DateTime.add(now, @max_years * 365, :day)) do
      {:ok, DateTime.truncate(utc, :second)}
    else
      {:error, _} -> {:error, "Choose a date and time."}
      :lt -> {:error, "Choose a time in the future."}
      :eq -> {:error, "Choose a time in the future."}
      :gt -> {:error, "Choose a time within #{@max_years} years."}
    end
  end

  def parse(_params), do: {:error, "Choose a date and time."}

  # datetime-local sends "YYYY-MM-DDTHH:MM" (no seconds)
  defp normalise(at) do
    if String.length(at) == 16, do: at <> ":00", else: at
  end

  @doc "How a reveal time is shown to owners."
  def label(%DateTime{} = at), do: Calendar.strftime(at, "%-d %B %Y, %H:%M UTC")

  @doc "The submitted time from either the form or the \"Open now\" button."
  def params(%{"reveal" => reveal}), do: reveal
  def params(params), do: params

  @doc """
  The form: posts `reveal[at]` and `reveal[offset]` to `event`; "Open now"
  sends an empty `at`. Read both with `params/1` then `parse/1`.
  """
  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :reveal_at, :any, default: nil
  attr :hint, :string, default: nil

  def reveal_form(assigns) do
    ~H"""
    <div class="flex flex-col gap-2.5">
      <p :if={@reveal_at} id={"#{@id}-state"} class="text-sm font-medium text-ks-amber-deep">
        <.icon name="hero-lock-closed" class="size-4" /> Sealed until {label(@reveal_at)}
      </p>
      <p :if={@hint} class="text-sm text-ks-muted">{@hint}</p>
      <form
        id={@id}
        phx-submit={@event}
        phx-hook=".TimezoneOffset"
        class="flex flex-wrap items-end gap-2.5"
      >
        <label class="flex flex-col gap-1 text-sm font-medium">
          Opens on
          <input
            type="datetime-local"
            name="reveal[at]"
            id={"#{@id}-at"}
            required
            class="input input-sm w-auto"
          />
        </label>
        <input type="hidden" name="reveal[offset]" id={"#{@id}-offset"} value="0" />
        <.button id={"#{@id}-save"} size="sm" variant="primary">
          {if @reveal_at, do: "Change", else: "Seal"}
        </.button>
        <.button
          :if={@reveal_at}
          id={"#{@id}-open"}
          type="button"
          size="sm"
          phx-click={@event}
          phx-value-at=""
        >
          Open now
        </.button>
      </form>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".TimezoneOffset">
        export default {
          mounted() {
            const at = this.el.querySelector("input[type=datetime-local]")
            const offset = this.el.querySelector("input[type=hidden][name$='[offset]']")
            const update = () => {
              const when = at.value ? new Date(at.value) : new Date()
              offset.value = String(when.getTimezoneOffset())
            }
            at.addEventListener("input", update)
            this.el.addEventListener("submit", update, true)
            update()
          }
        }
      </script>
    </div>
    """
  end
end
