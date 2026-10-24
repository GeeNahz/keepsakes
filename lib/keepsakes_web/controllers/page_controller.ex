defmodule KeepsakesWeb.PageController do
  use KeepsakesWeb, :controller

  def home(%{assigns: %{current_scope: %{user: %{}}}} = conn, _params) do
    redirect(conn, to: ~p"/albums")
  end

  def home(conn, _params) do
    render(conn, :home)
  end
end
