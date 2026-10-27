defmodule KeepsakesWeb.SiteRouter do
  @moduledoc """
  A customer's public site on their own domain (reached through
  `KeepsakesWeb.HostRouter`, which puts the domain in `conn.assigns.site`):

    * `/` - the albums they chose to show (`SiteLive.Index`)
    * `/:album` ... - the same guest pages as `/a/:slug` on the main site
      (access code, timeline, slideshow, report), found by album slug
      within the owner's albums

  Access codes still apply. Paths from the main site don't exist here.
  """
  use KeepsakesWeb, :router

  pipeline :site do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KeepsakesWeb.Layouts, :guest_root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", KeepsakesWeb do
    pipe_through :site

    post "/:album/access", GuestAccessController, :create
    get "/:album/photos/:id/download", GuestAccessController, :download

    # The domain travels in the LiveView session, so live pages know whose site it is
    live_session :site,
      root_layout: {KeepsakesWeb.Layouts, :guest_root},
      session: {KeepsakesWeb.GuestAccess, :site_session, []},
      on_mount: [
        {KeepsakesWeb.UserAuth, :mount_current_scope},
        {KeepsakesWeb.GuestAccess, :site}
      ] do
      live "/", SiteLive.Index, :index
      live "/:album", GuestLive.Access, :access
      live "/:album/timeline", GuestLive.Timeline, :timeline
      live "/:album/slideshow", GuestLive.Slideshow, :slideshow
      live "/:album/report", GuestLive.Report, :report
    end
  end
end
