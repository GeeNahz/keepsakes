defmodule KeepsakesWeb.PageController do
  use KeepsakesWeb, :controller

  def home(%{assigns: %{current_scope: %{user: %{}}}} = conn, _params) do
    redirect(conn, to: ~p"/app/albums")
  end

  def home(conn, _params) do
    render(conn, :home)
  end

  # Public: linked from sign-up, guest uploads and music uploads
  def terms(conn, _params) do
    render(conn, :terms,
      page_title: "Terms of use",
      version: Keepsakes.Accounts.terms_version()
    )
  end

  # `/app` on its own opens the album list
  def app(conn, _params), do: redirect(conn, to: ~p"/app/albums")

  # Settings opens on its first tab
  def settings(conn, _params), do: redirect(conn, to: ~p"/app/settings/profile")

  # Plans & billing lives in settings
  def billing(conn, _params), do: redirect(conn, to: ~p"/app/settings/billing")
end
