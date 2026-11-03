defmodule KeepsakesWeb.PageController do
  use KeepsakesWeb, :controller

  # The landing page is KeepsakesWeb.HomeLive

  # Public: linked from sign-up, guest uploads, music uploads and the footer
  def terms(conn, _params) do
    render(conn, :terms,
      page_title: "Terms of use",
      meta_description: "The terms for using Keepsake, including what you may upload and share.",
      version: Keepsakes.Accounts.terms_version()
    )
  end

  def privacy(conn, _params) do
    render(conn, :privacy,
      page_title: "Privacy",
      meta_description: "What Keepsake stores about you and your guests, why, and your rights.",
      updated: "November 2026"
    )
  end

  # `/app` on its own opens the album list
  def app(conn, _params), do: redirect(conn, to: ~p"/app/albums")

  # Settings opens on its first tab
  def settings(conn, _params), do: redirect(conn, to: ~p"/app/settings/profile")

  # Plans & billing lives in settings
  def billing(conn, _params), do: redirect(conn, to: ~p"/app/settings/billing")
end
