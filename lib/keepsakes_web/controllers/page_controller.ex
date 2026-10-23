defmodule KeepsakesWeb.PageController do
  use KeepsakesWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
