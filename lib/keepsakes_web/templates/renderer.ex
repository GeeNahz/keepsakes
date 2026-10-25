defmodule KeepsakesWeb.Templates.Renderer do
  @moduledoc """
  The code side of a guest template: function components that draw each
  guest page, wrapped in `<Layouts.app shell={:guest}>`. The guest
  LiveViews own state and events; a renderer only draws them, so a new
  layout is a new module implementing these callbacks plus an entry in
  `KeepsakesWeb.Templates`.

  Colours come from the `--color-ks-guest-*` tokens (and primary,
  secondary, accent), which the template's theme overrides, so one
  renderer serves many themed templates.

  Assigns every callback gets: `@flash`, `@album`, `@link`, `@owner_name`,
  `@access`, `@base_path`, `@preview?` and `@template`. Per page:

    * `access/1` - the code form (posts to `/a/:slug/access`)
    * `unavailable/1` - unknown or expired links (`@access` is
      `:missing` or `:expired`)
    * `timeline/1` - `@memories`, `@streams.entries`, `@last_side`,
      `@auto?`, `@downloads?`
    * `slideshow/1` - `@memories`
  """

  @callback access(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
  @callback unavailable(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
  @callback timeline(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
  @callback slideshow(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
end
