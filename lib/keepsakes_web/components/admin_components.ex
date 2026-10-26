defmodule KeepsakesWeb.AdminComponents do
  @moduledoc """
  Pieces of the admin portal: stat tiles and a small server-rendered SVG
  bar chart (one series per chart, so no legend; the title names it).
  Bars use the theme's primary colour, so they follow light/night.
  """
  use Phoenix.Component

  @doc """
  A headline number with a label and an optional note.

      <.stat id="stat-customers" label="Customers" value="1,204" note="+38 this week" />
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :note, :string, default: nil
  attr :navigate, :string, default: nil, doc: "makes the tile a link (e.g. to a filtered list)"

  def stat(%{navigate: path} = assigns) when is_binary(path) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class="group flex flex-col gap-1 rounded-box border border-base-300 bg-base-100 p-5 text-base-content no-underline transition-colors hover:border-primary"
    >
      <span class="flex items-center justify-between text-sm text-ks-muted">
        {@label}
        <span class="hero-arrow-right size-4 opacity-0 transition-opacity group-hover:opacity-100" />
      </span>
      <span class="font-display text-[28px] font-bold leading-tight tabular-nums">{@value}</span>
      <span :if={@note} class="text-[13px] text-ks-muted">{@note}</span>
    </.link>
    """
  end

  def stat(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col gap-1 rounded-box border border-base-300 bg-base-100 p-5">
      <span class="text-sm text-ks-muted">{@label}</span>
      <span class="font-display text-[28px] font-bold leading-tight tabular-nums">{@value}</span>
      <span :if={@note} class="text-[13px] text-ks-muted">{@note}</span>
    </div>
    """
  end

  @doc """
  Daily counts as bars, with a hover title on each day and the same
  numbers in a table underneath (for screen readers and exact values).

      <.bar_chart id="signups-chart" title="Sign-ups per day" points={[{~D[2026-10-01], 4}, ...]} unit="sign-ups" />
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :points, :list, required: true, doc: "`[{Date.t(), count}]`, oldest first"
  attr :unit, :string, required: true

  @width 600
  @height 180
  @top 12
  @bottom 24
  @left 32
  @gap 2

  def bar_chart(assigns) do
    points = assigns.points
    max = points |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0 end)
    scale_max = nice_max(max)
    plot_h = @height - @top - @bottom
    slot = (@width - @left) / max(length(points), 1)

    bars =
      points
      |> Enum.with_index()
      |> Enum.map(fn {{date, count}, i} ->
        h = if scale_max == 0, do: 0, else: count / scale_max * plot_h
        x = @left + i * slot

        %{
          date: date,
          count: count,
          x: x,
          slot: slot,
          bar_x: x + @gap / 2,
          bar_w: max(slot - @gap, 1),
          h: h,
          y: @height - @bottom - h
        }
      end)

    ticks =
      case points do
        [] -> []
        _ -> Enum.uniq([0, div(length(points) - 1, 2), length(points) - 1])
      end

    assigns =
      assign(assigns,
        bars: bars,
        scale_max: scale_max,
        total: Enum.sum(Enum.map(points, &elem(&1, 1))),
        ticks: Enum.map(ticks, &Enum.at(bars, &1)),
        width: @width,
        height: @height,
        top: @top,
        baseline: @height - @bottom,
        left: @left
      )

    ~H"""
    <figure id={@id} class="flex flex-col gap-3 rounded-box border border-base-300 bg-base-100 p-5">
      <figcaption class="flex items-baseline justify-between gap-3">
        <span class="font-bold">{@title}</span>
        <span class="text-sm text-ks-muted tabular-nums">{@total} in 30 days</span>
      </figcaption>
      <svg
        viewBox={"0 0 #{@width} #{@height}"}
        class="h-auto w-full overflow-visible"
        role="img"
        aria-label={"#{@title}: #{@total} #{@unit} in the last 30 days"}
      >
        <%!-- Recessive grid: the top of the scale and the baseline --%>
        <line
          x1={@left}
          x2={@width}
          y1={@top}
          y2={@top}
          class="stroke-base-300"
          stroke-dasharray="3 3"
        />
        <text
          :if={@scale_max > 0}
          x={@left - 6}
          y={@top + 4}
          text-anchor="end"
          class="fill-ks-muted text-[11px]"
        >
          {@scale_max}
        </text>
        <text
          :if={@total == 0}
          x={(@left + @width) / 2}
          y={(@top + @baseline) / 2}
          text-anchor="middle"
          class="fill-ks-muted text-[13px]"
        >
          None in the last 30 days
        </text>
        <text x={@left - 6} y={@baseline + 4} text-anchor="end" class="fill-ks-muted text-[11px]">
          0
        </text>

        <g :for={bar <- @bars} class="group">
          <%!-- The whole day column is the hover target, not just the bar --%>
          <rect x={bar.x} y={@top} width={bar.slot} height={@baseline - @top} class="fill-transparent">
            <title>{Calendar.strftime(bar.date, "%a %d %b")}: {bar.count} {@unit}</title>
          </rect>
          <path
            :if={bar.count > 0}
            d={bar_path(bar.bar_x, bar.y, bar.bar_w, bar.h)}
            class="pointer-events-none fill-primary transition-opacity group-hover:opacity-75"
          />
        </g>

        <line x1={@left} x2={@width} y1={@baseline} y2={@baseline} class="stroke-base-300" />
        <text
          :for={bar <- @ticks}
          x={bar.x + bar.slot / 2}
          y={@height - 6}
          text-anchor="middle"
          class="fill-ks-muted text-[11px]"
        >
          {Calendar.strftime(bar.date, "%d %b")}
        </text>
      </svg>
      <details>
        <summary class="cursor-pointer text-sm text-primary">Show as a table</summary>
        <table class="table table-xs mt-2">
          <thead>
            <tr>
              <th>Day</th><th class="text-right">{String.capitalize(@unit)}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={bar <- Enum.reverse(@bars)}>
              <td>{Calendar.strftime(bar.date, "%a %d %b")}</td>
              <td class="text-right tabular-nums">{bar.count}</td>
            </tr>
          </tbody>
        </table>
      </details>
    </figure>
    """
  end

  # Rounded top corners (4px), square at the baseline
  defp bar_path(x, y, w, h) do
    r = Enum.min([4, w / 2, h])

    "M#{f(x)},#{f(y + h)} V#{f(y + r)} Q#{f(x)},#{f(y)} #{f(x + r)},#{f(y)} " <>
      "H#{f(x + w - r)} Q#{f(x + w)},#{f(y)} #{f(x + w)},#{f(y + r)} V#{f(y + h)} Z"
  end

  defp f(n), do: :erlang.float_to_binary(n / 1, decimals: 1)

  # A round top for the scale: 4 → 5, 13 → 15, 230 → 250
  defp nice_max(0), do: 0

  defp nice_max(max) do
    magnitude = :math.pow(10, floor(:math.log10(max)))

    step =
      Enum.find([1, 2, 2.5, 5, 10], fn s -> s * magnitude >= max end)

    round(step * magnitude)
  end
end
