defmodule Keepsakes.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Keepsakes.{Repo, Storage}

  alias Keepsakes.Accounts.{User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc "Gets a user by ID, or nil."
  def get_user(id), do: Repo.get(User, id)

  ## User registration

  @doc """
  Registers a user with first name, last name, email and password.

  The account starts unconfirmed; see `deliver_login_instructions/2`. It
  gets its own invite code, and `referral_code:` (from an invite link)
  records who invited it; unknown codes are ignored.

  ## Examples

      iex> register_user(%{first_name: "Ada", email: "ada@example.com", password: "..."})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs, opts \\ []) do
    referrer = referrer(opts[:referral_code])

    changeset =
      %User{}
      |> User.registration_changeset(attrs)
      |> Ecto.Changeset.put_change(:referral_code, new_referral_code())
      |> Ecto.Changeset.put_change(:referred_by_id, referrer && referrer.id)
      |> Ecto.Changeset.unique_constraint(:referral_code)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, changeset)
    |> Keepsakes.Billing.start_trial(:user)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  # Invite codes: 8 characters, no lookalikes (0/O, 1/I)
  @code_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

  defp new_referral_code,
    do: for(_ <- 1..8, into: "", do: <<Enum.random(@code_alphabet)>>)

  defp referrer(code) when is_binary(code) and code != "" do
    Repo.get_by(User, referral_code: code |> String.trim() |> String.upcase())
  end

  defp referrer(_code), do: nil

  @doc """
  Returns a changeset for live validation of the registration form.

  Uniqueness is not checked and the password is not hashed.
  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, validate_unique: false, hash_password: false)
  end

  @doc """
  Updates the user's first and last name.
  """
  def update_user_name(%User{} = user, attrs) do
    user
    |> User.name_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns a changeset for changing the user's name.
  """
  def change_user_name(%User{} = user, attrs \\ %{}) do
    User.name_changeset(user, attrs)
  end

  ## Profile, preferences and sharing defaults (settings tabs)

  def change_profile(%User{} = user, attrs \\ %{}), do: User.profile_changeset(user, attrs)

  def update_profile(%User{} = user, attrs),
    do: user |> User.profile_changeset(attrs) |> Repo.update()

  def change_notifications(%User{} = user, attrs \\ %{}),
    do: User.notifications_changeset(user, attrs)

  def update_notifications(%User{} = user, attrs),
    do: user |> User.notifications_changeset(attrs) |> Repo.update()

  def change_sharing_defaults(%User{} = user, attrs \\ %{}),
    do: User.sharing_defaults_changeset(user, attrs)

  def update_sharing_defaults(%User{} = user, attrs),
    do: user |> User.sharing_defaults_changeset(attrs) |> Repo.update()

  @avatar_size 256

  @doc """
  Makes the image at `path` the user's profile photo: cropped to a centred
  square, resized to #{@avatar_size} px and stored as WebP. The previous
  photo is removed.
  """
  @spec set_avatar(User.t(), Path.t()) :: {:ok, User.t()} | {:error, term()}
  def set_avatar(%User{} = user, path) do
    key = "users/#{user.id}/avatar/#{Ecto.UUID.generate()}.webp"

    with {:ok, image} <- Image.thumbnail(path, @avatar_size, crop: :center, autorotate: true),
         {:ok, data} <- Image.write(image, :memory, suffix: ".webp", quality: 85),
         :ok <- Storage.put(key, data, content_type: "image/webp"),
         {:ok, updated} <- user |> Ecto.Changeset.change(avatar_key: key) |> Repo.update() do
      if user.avatar_key, do: Storage.delete(user.avatar_key)
      {:ok, updated}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, _reason} -> {:error, :unreadable}
    end
  end

  @doc "Removes the profile photo (initials show instead)."
  def remove_avatar(%User{avatar_key: nil} = user), do: {:ok, user}

  def remove_avatar(%User{avatar_key: key} = user) do
    {:ok, updated} = user |> Ecto.Changeset.change(avatar_key: nil) |> Repo.update()
    Storage.delete(key)
    {:ok, updated}
  end

  @doc "A short-lived URL for the user's profile photo, or nil."
  def avatar_url(%User{avatar_key: nil}), do: nil
  def avatar_url(%User{avatar_key: key}), do: Storage.url(key)

  ## Signed-in devices

  @doc "The user's live sessions, newest first."
  def list_sessions(%User{id: user_id}) do
    from(t in UserToken,
      where: t.user_id == ^user_id and t.context == "session",
      where: t.inserted_at > ago(14, "day"),
      order_by: [desc: t.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Ends one of the user's sessions. Returns its token for disconnecting."
  def delete_session(%User{id: user_id}, session_id) do
    case Repo.get_by(UserToken, id: session_id, user_id: user_id, context: "session") do
      nil -> {:error, :not_found}
      token -> Repo.delete(token)
    end
  end

  @doc "Ends every session except `current_token`. Returns the ended tokens."
  def delete_other_sessions(%User{id: user_id}, current_token) do
    {_count, tokens} =
      from(t in UserToken,
        where: t.user_id == ^user_id and t.context == "session" and t.token != ^current_token,
        select: t
      )
      |> Repo.delete_all()

    tokens
  end

  ## Deleting an account

  @deletion_grace_days 14

  @doc "Days an account waits, paused, before it's deleted for good."
  def deletion_grace_days, do: @deletion_grace_days

  @doc """
  Pauses the account for deletion: signs it out everywhere (returns the
  tokens to disconnect), and from now shared links stop working and
  renewals stop. Logging in within #{@deletion_grace_days} days offers to
  restore it; after that `purge_deleted/1` removes everything.
  """
  @spec request_deletion(User.t()) :: {:ok, User.t(), [UserToken.t()]}
  def request_deletion(%User{} = user) do
    Repo.transact(fn ->
      user =
        user
        |> Ecto.Changeset.change(deletion_requested_at: DateTime.utc_now(:second))
        |> Repo.update!()

      {_count, tokens} =
        from(t in UserToken, where: t.user_id == ^user.id, select: t) |> Repo.delete_all()

      {:ok, {user, tokens}}
    end)
    |> case do
      {:ok, {user, tokens}} ->
        UserNotifier.deliver_deletion_scheduled(user, deletion_date(user))
        {:ok, user, tokens}
    end
  end

  @doc "When a paused account will be deleted."
  def deletion_date(%User{deletion_requested_at: at}),
    do: DateTime.add(at, @deletion_grace_days, :day)

  @doc "Cancels a requested deletion."
  def restore_account(%User{} = user),
    do: user |> Ecto.Changeset.change(deletion_requested_at: nil) |> Repo.update()

  @doc """
  Deletes, for good, every account paused more than #{@deletion_grace_days}
  days ago: its stored files, then the user row (albums, subscriptions and
  the rest go with it). Returns how many were deleted.
  """
  def purge_deleted(now \\ DateTime.utc_now(:second)) do
    cutoff = DateTime.add(now, -@deletion_grace_days, :day)

    from(u in User, where: u.deletion_requested_at <= ^cutoff)
    |> Repo.all()
    |> Enum.count(fn user ->
      {:ok, keys} = Storage.list("users/#{user.id}/")
      Enum.each(keys, &Storage.delete/1)
      match?({:ok, _}, Repo.delete(user))
    end)
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Keepsakes.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Keepsakes.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user, device \\ %{}) do
    {token, user_token} = UserToken.build_session_token(user, device)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link (the emailed sign-in, confirmation and
  password-reset links all use this).

  `current_user` is whoever is logged in on the browser that opened the link,
  or `nil`. There are four cases:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user is unconfirmed and has no password. They get confirmed,
     logged in, and all their tokens, including sessions, are expired.

  3. The user is unconfirmed, has a password, and is the `current_user`.
     This is the normal sign-up path: they registered with a password, were
     logged in, and are now confirming from the same browser. They get
     confirmed, and every token is expired so a fresh session is issued.

  4. The user is unconfirmed, has a password, and is NOT the `current_user`.
     Someone may have registered this email first with their own password
     ("credential pre-stuffing", see `mix help phx.gen.auth`). Owning the
     inbox proves ownership of the account, so it is confirmed, the password
     is removed and every session is expired. The owner then sets their own
     password.
  """
  def login_user_by_magic_link(token, current_user \\ nil) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      {%User{confirmed_at: nil, hashed_password: hash} = user, _token} when not is_nil(hash) ->
        changeset = User.confirm_changeset(user)

        changeset =
          if current_user && current_user.id == user.id,
            do: changeset,
            else: User.clear_password_changeset(changeset)

        update_user_and_delete_all_tokens(changeset)

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/app/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Delivers "reset your password" instructions.

  The link is a normal 15-minute magic link; opening it logs the user in
  (in sudo mode) and sends them to choose a new password.
  """
  def deliver_password_reset_instructions(%User{} = user, reset_url_fun)
      when is_function(reset_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_password_reset_instructions(user, reset_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
