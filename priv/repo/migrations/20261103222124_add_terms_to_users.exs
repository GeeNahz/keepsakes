defmodule Keepsakes.Repo.Migrations.AddTermsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # When and which version of the Terms of use the account agreed to
      add :terms_accepted_at, :utc_datetime
      add :terms_version, :string
    end
  end
end
