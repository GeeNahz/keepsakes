defmodule KeepsakesWeb.Router do
  use KeepsakesWeb, :router

  import KeepsakesWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KeepsakesWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Photos on local disk, authorised by the signed token in the URL itself
  # (no session), so the same links work for owners and guests.
  scope "/media", KeepsakesWeb do
    get "/:token", MediaController, :show
  end

  scope "/", KeepsakesWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Payment provider callbacks: no session or CSRF; each provider signs its own
  scope "/webhooks", KeepsakesWeb do
    pipe_through :api

    post "/flutterwave", WebhookController, :flutterwave
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:keepsakes, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: KeepsakesWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/dev", KeepsakesWeb.Dev do
      pipe_through :browser

      live "/components", ComponentsLive
    end
  end

  ## Guest pages for shared albums (always the night theme, never indexed)

  scope "/a", KeepsakesWeb do
    pipe_through :browser

    post "/:slug/access", GuestAccessController, :create
    get "/:slug/photos/:id/download", GuestAccessController, :download

    # The owner previews how guests will see an album, shared or not
    live_session :guest_preview,
      root_layout: {KeepsakesWeb.Layouts, :guest_root},
      on_mount: [
        {KeepsakesWeb.UserAuth, :mount_current_scope},
        {KeepsakesWeb.GuestAccess, :preview}
      ] do
      live "/preview/:album_slug/timeline", GuestLive.Timeline, :preview
      live "/preview/:album_slug/slideshow", GuestLive.Slideshow, :preview
      # The same, in a template the album doesn't use yet (template picker)
      live "/preview/:album_slug/:template/timeline", GuestLive.Timeline, :preview
      live "/preview/:album_slug/:template/slideshow", GuestLive.Slideshow, :preview
    end

    # Anyone with the link; the code unlocks timeline and slideshow
    live_session :guest,
      root_layout: {KeepsakesWeb.Layouts, :guest_root},
      on_mount: [
        {KeepsakesWeb.UserAuth, :mount_current_scope},
        {KeepsakesWeb.GuestAccess, :link}
      ] do
      live "/:slug", GuestLive.Access, :access
      live "/:slug/timeline", GuestLive.Timeline, :timeline
      live "/:slug/slideshow", GuestLive.Slideshow, :slideshow
      # Anyone with the link, code or not, can report the album
      live "/:slug/report", GuestLive.Report, :report
    end
  end

  ## Authentication routes

  # Owner portal under /app: everything here needs a logged-in user
  # (the super-admin portal lives on its own admin.<host> subdomain)
  scope "/app", KeepsakesWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/", PageController, :app
    get "/settings", PageController, :settings
    get "/billing", PageController, :billing

    live_session :require_authenticated_user,
      on_mount: [{KeepsakesWeb.UserAuth, :require_authenticated}, KeepsakesWeb.OwnerShell] do
      live "/albums", AlbumLive.Index, :index
      # One LiveView for the album, its upload screen and the memory editor,
      # so files picked on the album page keep uploading across the patch
      live "/albums/:slug", AlbumLive.Show, :show
      live "/albums/:slug/upload", AlbumLive.Show, :upload
      live "/albums/:slug/memories/:id", AlbumLive.Show, :edit
      live "/albums/:slug/share", AlbumLive.Share, :share
      live "/albums/:slug/template", AlbumLive.Template, :template
      # Settings: one LiveView per tab (KeepsakesWeb.SettingsComponents)
      live "/settings/profile", SettingsLive.Profile, :profile
      live "/settings/account", SettingsLive.Account, :edit
      live "/settings/account/confirm-email/:token", SettingsLive.Account, :confirm_email
      live "/settings/security", SettingsLive.Security, :security
      live "/settings/notifications", SettingsLive.Notifications, :notifications
      live "/settings/sharing", SettingsLive.Sharing, :sharing
      live "/settings/templates", SettingsLive.Templates, :templates
      live "/settings/billing", BillingLive.Index, :index
      live "/settings/billing/invoices/:id", BillingLive.Invoice, :show
      live "/settings/referrals", SettingsLive.Referrals, :referrals
      live "/settings/domains", SettingsLive.Domains, :domains
      live "/settings/privacy", SettingsLive.Privacy, :privacy

      live "/help", SupportLive.Index, :index
      live "/help/:number", SupportLive.Show, :show
    end

    # Flutterwave's card page sends the owner back here
    get "/billing/return", BillingController, :return
    get "/settings/privacy/exports/:id", DataExportController, :show
    post "/settings/account/update-password", UserSessionController, :update_password
    post "/confirm-email/resend", UserConfirmationController, :create
  end

  # Sign-in pages under /auth: work logged out, but know about the current
  # user if any
  scope "/auth", KeepsakesWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{KeepsakesWeb.UserAuth, :mount_current_scope}] do
      live "/register", UserLive.Registration, :new
      live "/log-in", UserLive.Login, :new
      live "/log-in/:token", UserLive.Confirmation, :new
      live "/reset-password", UserLive.ResetPassword, :new
    end

    post "/log-in", UserSessionController, :create
    delete "/log-out", UserSessionController, :delete

    # After a correct password or link: two-step code, or restoring a
    # paused account (KeepsakesWeb.LoginStepController)
    get "/two-step", LoginStepController, :two_step
    post "/two-step", LoginStepController, :verify_two_step
    delete "/two-step/cancel", LoginStepController, :cancel
    get "/restore", LoginStepController, :restore
    post "/restore", LoginStepController, :do_restore
  end
end
