defmodule KeepsakesWeb.PageController do
  use KeepsakesWeb, :controller

  def home(%{assigns: %{current_scope: %{user: %{}}}} = conn, _params) do
    redirect(conn, to: ~p"/app/albums")
  end

  def home(conn, _params) do
    render(conn, :home)
  end

  # `/app` on its own opens the album list
  def app(conn, _params), do: redirect(conn, to: ~p"/app/albums")
end
