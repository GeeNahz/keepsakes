defmodule Keepsakes.Albums.Member do
  @moduledoc """
  A collaborator on an album (`Keepsakes.Albums.Members`): invited by email,
  joined when they accept (`user_id`, `accepted_at`).

  Roles:

    * `"editor"` - adds, edits and reorders photos, reviews guest photos
      and guestbook notes
    * `"viewer"` - sees the album and every photo, changes nothing
  """
  use Keepsakes.Schema

  @roles ~w(editor viewer)

  schema "album_members" do
    field :email, :string
    field :role, :string
    field :token_hash, :binary, redact: true
    field :invited_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :album, Keepsakes.Albums.Album
    belongs_to :user, Keepsakes.Accounts.User
    belongs_to :invited_by, Keepsakes.Accounts.User

    timestamps()
  end

  def roles, do: @roles

  @doc "The invite form: email and role."
  def invite_changeset(member, attrs) do
    member
    |> cast(attrs, [:email, :role])
    |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:email, :role])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+\.[^@,;\s]+$/,
      message: "must be an email address"
    )
    |> validate_length(:email, max: 160)
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:email,
      name: :album_members_album_id_email_index,
      message: "is already invited to this album"
    )
  end

  @doc "Changing an existing member's role."
  def role_changeset(member, attrs) do
    member
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, @roles)
  end

  def accepted?(%__MODULE__{accepted_at: at}), do: not is_nil(at)

  @doc "Role as an atom: `:editor` or `:viewer`."
  def role_atom(%__MODULE__{role: "editor"}), do: :editor
  def role_atom(%__MODULE__{role: "viewer"}), do: :viewer
end
