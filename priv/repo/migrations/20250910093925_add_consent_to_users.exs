defmodule Glific.Repo.Migrations.AddConsentToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :consent_for_updates, :boolean, default: false, null: false
    end
  end
end
