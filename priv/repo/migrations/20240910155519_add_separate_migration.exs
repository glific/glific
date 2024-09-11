defmodule Glific.Repo.Migrations.AddSeparateMigration do
  use Ecto.Migration

  def change do
    alter table(:wa_managed_phones) do
      add :status, :string,
        comment: "status of the phone connected to Maytapi to see whether it is active or not"
    end
  end
end
