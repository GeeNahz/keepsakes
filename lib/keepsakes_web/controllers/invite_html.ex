defmodule KeepsakesWeb.InviteHTML do
  @moduledoc "The collaborator invitation page (`KeepsakesWeb.InviteController`)."
  use KeepsakesWeb, :html

  embed_templates "invite_html/*"

  def role_text("editor"), do: "an editor (you can add and edit photos)"
  def role_text(_role), do: "a viewer (you can see every photo)"
end
