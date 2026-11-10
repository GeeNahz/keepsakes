defmodule Keepsakes.Accounts.TwoStep do
  @moduledoc """
  Optional two-step login with an authenticator app (TOTP, RFC 6238).

  Turning it on: `new_secret/0` → show `qr_svg/2` → the user types a code
  from their app → `enable/3` saves the (encrypted) secret and returns ten
  single-use recovery codes, shown once and stored hashed.

  At login (`verify/2`) either a current 6-digit code or an unused
  recovery code works; a recovery code is crossed off when used. Codes
  are accepted for the 30-second step before and after the current one,
  to allow for clock drift.
  """
  alias Keepsakes.Accounts.User
  alias Keepsakes.Repo

  @issuer "Keepsake"
  @recovery_count 10

  @doc "A fresh random secret for setting up an app."
  def new_secret, do: NimbleTOTP.secret()

  @doc "The `otpauth://` link apps read from the QR code."
  def uri(%User{email: email}, secret),
    do: NimbleTOTP.otpauth_uri("#{@issuer}:#{email}", secret, issuer: @issuer)

  @doc "The QR code for `uri/2`, as an inline SVG string."
  def qr_svg(%User{} = user, secret),
    do: user |> uri(secret) |> EQRCode.encode() |> EQRCode.svg(width: 200)

  @doc "The secret in letters, for typing into an app by hand."
  def manual_key(secret),
    do:
      secret
      |> Base.encode32(padding: false)
      |> String.graphemes()
      |> Enum.chunk_every(4)
      |> Enum.map_join(" ", &Enum.join/1)

  @doc """
  Turns two-step login on when `code` matches `secret`. Returns the
  plain recovery codes to show once.
  """
  @spec enable(User.t(), binary(), String.t()) ::
          {:ok, User.t(), [String.t()]} | {:error, :invalid_code}
  def enable(%User{} = user, secret, code) do
    if valid_totp?(secret, code) do
      codes = new_recovery_codes()

      user =
        user
        |> Ecto.Changeset.change(
          totp_secret: secret,
          totp_enabled_at: DateTime.utc_now(:second),
          recovery_codes: Enum.map(codes, &hash/1)
        )
        |> Repo.update!()

      {:ok, user, codes}
    else
      {:error, :invalid_code}
    end
  end

  @doc "Turns two-step login off (after a current code or recovery code)."
  @spec disable(User.t(), String.t()) :: {:ok, User.t()} | {:error, :invalid_code}
  def disable(%User{} = user, code) do
    with {:ok, user} <- verify(user, code) do
      {:ok,
       user
       |> Ecto.Changeset.change(totp_secret: nil, totp_enabled_at: nil, recovery_codes: [])
       |> Repo.update!()}
    end
  end

  @doc "New recovery codes (the old ones stop working), after a current code."
  @spec regenerate_recovery_codes(User.t(), String.t()) ::
          {:ok, User.t(), [String.t()]} | {:error, :invalid_code}
  def regenerate_recovery_codes(%User{} = user, code) do
    with {:ok, user} <- verify(user, code) do
      codes = new_recovery_codes()

      user =
        user |> Ecto.Changeset.change(recovery_codes: Enum.map(codes, &hash/1)) |> Repo.update!()

      {:ok, user, codes}
    end
  end

  @doc "Whether the user has two-step login on."
  def enabled?(%User{totp_enabled_at: at}), do: not is_nil(at)

  @doc """
  Checks a login code: a current app code, or an unused recovery code
  (which is then used up).
  """
  @spec verify(User.t(), String.t()) :: {:ok, User.t()} | {:error, :invalid_code}
  def verify(%User{totp_secret: secret} = user, code)
      when is_binary(secret) and is_binary(code) do
    cleaned = code |> String.replace(~r/[\s-]/, "") |> String.upcase()

    cond do
      valid_totp?(secret, cleaned) ->
        {:ok, user}

      hash(cleaned) in user.recovery_codes ->
        remaining = List.delete(user.recovery_codes, hash(cleaned))
        {:ok, user |> Ecto.Changeset.change(recovery_codes: remaining) |> Repo.update!()}

      true ->
        {:error, :invalid_code}
    end
  end

  def verify(_user, _code), do: {:error, :invalid_code}

  defp valid_totp?(secret, code) when is_binary(code) do
    code = String.replace(code, ~r/\s/, "")
    now = System.os_time(:second)

    Regex.match?(~r/\A\d{6}\z/, code) and
      Enum.any?([now - 30, now, now + 30], &NimbleTOTP.valid?(secret, code, time: &1))
  end

  defp valid_totp?(_secret, _code), do: false

  # XXXX-XXXX, no lookalike characters
  defp new_recovery_codes do
    alphabet = ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    for _ <- 1..@recovery_count do
      code = for(_ <- 1..8, into: "", do: <<Enum.random(alphabet)>>)
      String.slice(code, 0, 4) <> "-" <> String.slice(code, 4, 4)
    end
  end

  # Recovery codes are random enough that a plain hash is safe
  defp hash(code) do
    normalized = code |> String.replace("-", "") |> String.upcase()
    :crypto.hash(:sha256, normalized) |> Base.encode16(case: :lower)
  end
end
