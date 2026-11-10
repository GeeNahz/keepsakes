defmodule KeepsakesWeb.Templates do
  @moduledoc """
  Maps a template's renderer name to the module that draws it, and turns
  its theme into the assigns the guest root layout reads.
  """
  alias Keepsakes.Templates.{Template, Theme}

  @renderers %{"trail" => KeepsakesWeb.Templates.Trail}

  @doc "The renderer module for `template`."
  def renderer(%Template{renderer: name}), do: Map.fetch!(@renderers, name)

  @doc """
  Assigns for a guest page drawn with `template`: `@template`, `@renderer`,
  and the root layout's `@theme_style` and `@color_scheme`.
  """
  def assigns(%Template{} = template) do
    [
      template: template,
      renderer: renderer(template),
      theme_style: Theme.css_vars(template.theme),
      color_scheme: Theme.scheme(template.theme)
    ]
  end
end
