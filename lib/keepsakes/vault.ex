defmodule Keepsakes.Vault do
  @moduledoc """
  Cloak vault used to encrypt sensitive columns at rest (share access codes,
  TOTP secrets, payment gateway tokens). Ciphers are configured at runtime
  from `CLOAK_KEY`; see `config/runtime.exs`.
  """
  use Cloak.Vault, otp_app: :keepsakes
end
