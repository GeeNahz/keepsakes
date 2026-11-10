defmodule Keepsakes.Support.Ticket do
  @moduledoc """
  A support conversation. Opened by an owner from Help, or by a guest
  reporting an album (`user_id` nil, `album_id` set).

  Status: `open` (new), `awaiting_staff` (the customer wrote last),
  `awaiting_user` (support wrote last), `resolved` (marked solved; the
  customer can reopen or rate it) and `closed` (no more replies).
  """
  use Keepsakes.Schema

  alias Keepsakes.Support.Message

  @type t :: %__MODULE__{}

  @categories ~w(billing technical account abuse other)

  schema "tickets" do
    field :number, :string
    field :reporter_email, :string
    field :subject, :string
    field :category, :string
    field :priority, :string, default: "normal"
    field :status, :string, default: "open"
    field :first_response_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :closed_at, :utc_datetime
    field :last_activity_at, :utc_datetime
    field :rating, :integer
    field :rating_comment, :string
    field :rated_at, :utc_datetime

    # The first message, typed with the subject on the Help form
    field :body, :string, virtual: true

    belongs_to :user, Keepsakes.Accounts.User
    belongs_to :album, Keepsakes.Albums.Album
    belongs_to :share_link, Keepsakes.Sharing.ShareLink
    belongs_to :assignee, Keepsakes.Accounts.User
    has_many :messages, Message

    timestamps()
  end

  @doc "Categories as `{label, value}` for the Help form."
  def category_options do
    [
      {"Billing and plans", "billing"},
      {"Something isn't working", "technical"},
      {"My account", "account"},
      {"Report a problem with content", "abuse"},
      {"Something else", "other"}
    ]
  end

  @doc "The Help form: category, subject and the first message."
  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [:category, :subject, :body])
    |> update_change(:subject, &String.trim/1)
    |> update_change(:body, &String.trim/1)
    |> validate_required([:category, :subject, :body], message: "Please fill this in")
    |> validate_inclusion(:category, @categories)
    |> validate_length(:subject, max: 120)
    |> validate_length(:body, max: 5000)
  end

  @doc "Whether the customer can still write on it."
  def open?(%__MODULE__{status: status}), do: status != "closed"

  @doc "A short label for the status, from the customer's side."
  def status_label("open"), do: "Received"
  def status_label("awaiting_staff"), do: "Waiting on support"
  def status_label("awaiting_user"), do: "Waiting on you"
  def status_label("resolved"), do: "Solved"
  def status_label("closed"), do: "Closed"
end
