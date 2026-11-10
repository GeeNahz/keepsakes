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
  `@access`, `@base_path`, `@preview?`, `@template` and `@branding?`
  (show "Made with Keepsake"; off on plans with `remove_branding`). Per page:

    * `access/1` - the code form (posts to `/a/:slug/access`)
    * `unavailable/1` - unknown or expired links (`@access` is
      `:missing` or `:expired`)
    * `timeline/1` - `@memories`, `@streams.entries`, `@last_side`,
      `@auto?`, `@downloads?`; should link to `@base_path <> "/report"`
      (Report this album) outside the owner's preview
    * `slideshow/1` - `@memories` (never sealed ones), `@music_url` (or nil:
      show a "Play with music" control when set)
    * `add/1` - guest uploads: `@form` (guest_name, title, month, year,
      caption, rights), `@uploads.photos`, `@added`, `@error`,
      `@max_upload_mb`, `@max_entries`; events `validate`, `send`,
      `cancel_entry`
    * `guestbook/1` - `@notes` (approved, plus the guest's own pending),
      `@form` (name, message); events `validate`, `sign`
    * `sealed/1` - the album is a time capsule that hasn't opened:
      `@album.reveal_at`

  Engagement assigns on every page: `@uploads?` / `@reactions?` (link to
  `/add` and `/guestbook` when true), `@visitor_key`, `@sealed?`. In
  `timeline/1`, `@now` decides which memories are sealed
  (`Keepsakes.Albums.Memory.sealed?/2`): draw a sealed placeholder for
  those (their photo and text are already removed). Each entry may carry
  `:hearts` and `:hearted?`; a heart sends `"heart"` with the memory id.
  """

  @callback access(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
  @callback unavailable(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
  @callback timeline(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
  @callback slideshow(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
  @callback add(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
  @callback guestbook(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
  @callback sealed(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
end
