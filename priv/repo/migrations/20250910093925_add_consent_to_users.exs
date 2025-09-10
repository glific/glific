defmodule Glific.Repo.Migrations.AddConsentToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :consent, :boolean, default: false, null: false
    end
  end
end
