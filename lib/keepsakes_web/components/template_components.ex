defmodule KeepsakesWeb.TemplateComponents do
  @moduledoc """
  Template gallery pieces: a miniature of a template drawn with its own
  theme (so the card shows real colours, not a screenshot), the gallery
  card, and the "Create your own" placeholder.
  """
  use KeepsakesWeb, :html

  alias Keepsakes.Templates.Theme

  @doc """
  A small scene in the template's colours: the dashed trail, two
  polaroids (the album's own photos when given) and the album title.
  """
  attr :template, :map, required: true
  attr :title, :string, default: "Our album"
  attr :photos, :list, default: [], doc: "up to two photo URLs"
  attr :class, :any, default: nil

  def template_scene(assigns) do
    ~H"""
    <%!-- The guest base theme, so primary etc. don't follow the owner's light/dark mode --%>
    <div
      data-theme="keepsake-night"
      style={Theme.css_vars(@template.theme)}
      aria-hidden="true"
      class={[
        "relative aspect-[16/10] overflow-hidden rounded-xl bg-ks-guest text-ks-guest-ink",
        @class
      ]}
    >
      <svg
        viewBox="0 0 320 200"
        preserveAspectRatio="none"
        class="absolute inset-0 size-full"
      >
        <path
          d="M40 200 C 60 150, 250 150, 230 110 S 100 80, 160 54"
          fill="none"
          class="stroke-primary"
          stroke-width="2"
          stroke-dasharray="2 7"
          stroke-linecap="round"
        />
      </svg>
      <div class="absolute inset-x-0 top-[10%] flex justify-center">
        <span class="max-w-[80%] truncate font-display text-base font-bold leading-tight">
          {@title}
        </span>
      </div>
      <div
        :for={
          {position, index} <-
            Enum.with_index(["left-[12%] top-[38%] -rotate-6", "right-[12%] top-[48%] rotate-4"])
        }
        class={[
          "absolute w-[30%] rounded-sm bg-ks-guest-paper p-1 pb-3 shadow-[0_8px_16px_var(--color-ks-guest-shadow)]",
          position
        ]}
      >
        <div class={[
          "aspect-[5/4] overflow-hidden",
          if(index == 0, do: "bg-ks-tint-sand", else: "bg-ks-tint-sage")
        ]}>
          <img
            :if={Enum.at(@photos, index)}
            src={Enum.at(@photos, index)}
            alt=""
            loading="lazy"
            class="size-full object-cover"
          />
        </div>
      </div>
    </div>
    """
  end

  @doc "A template in the gallery, with its preview and pick actions in `:actions`."
  attr :id, :string, required: true
  attr :template, :map, required: true
  attr :current, :boolean, default: false
  attr :title, :string, default: "Our album"
  attr :photos, :list, default: []
  slot :actions

  def template_card(assigns) do
    ~H"""
    <article
      id={@id}
      class={[
        "flex flex-col gap-4 rounded-2xl border bg-base-100 p-4 transition-shadow hover:shadow-[0_12px_30px_rgba(27,30,39,0.08)]",
        if(@current, do: "border-primary ring-1 ring-primary", else: "border-base-300")
      ]}
    >
      <.template_scene template={@template} title={@title} photos={@photos} />
      <div class="flex flex-col gap-1.5 px-1">
        <div class="flex items-center gap-2">
          <h2 class="text-lg font-bold">{@template.name}</h2>
          <span :if={@current} class="badge badge-sm badge-primary">In use</span>
          <span
            :if={@template.premium}
            class="badge badge-sm border-0 bg-ks-amber-soft text-ks-amber-deep"
          >
            Premium
          </span>
        </div>
        <p :if={@template.description} class="text-sm text-ks-muted">{@template.description}</p>
      </div>
      <div :if={@actions != []} class="mt-auto flex flex-wrap gap-2.5 px-1 pb-1">
        {render_slot(@actions)}
      </div>
    </article>
    """
  end

  @doc "Placeholder card for user-made templates (not built yet)."
  attr :id, :string, required: true

  def create_your_own_card(assigns) do
    ~H"""
    <article
      id={@id}
      class="flex flex-col gap-4 rounded-2xl border border-dashed border-base-300 bg-base-100/60 p-4"
    >
      <div class="flex aspect-[16/10] flex-col items-center justify-center gap-2 rounded-xl bg-base-200 text-ks-muted">
        <.icon name="hero-paint-brush" class="size-8" />
      </div>
      <div class="flex flex-col gap-1.5 px-1">
        <div class="flex items-center gap-2">
          <h2 class="text-lg font-bold">Create your own</h2>
          <span class="badge badge-sm badge-ghost">Coming soon</span>
        </div>
        <p class="text-sm text-ks-muted">
          Pick your own colours and fonts for a look that's all yours.
        </p>
      </div>
      <div class="mt-auto px-1 pb-1">
        <.button id={"#{@id}-button"} type="button" disabled>Create your own</.button>
      </div>
    </article>
    """
  end
end
