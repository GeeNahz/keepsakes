defmodule Keepsakes.Encrypted.Binary do
  @moduledoc "Ecto type for a string/binary column encrypted with `Keepsakes.Vault`."
  use Cloak.Ecto.Binary, vault: Keepsakes.Vault
end
