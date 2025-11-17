defmodule Glific.Repo.Migrations.AddStatusEnumToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :trial_metadata, :map,
        default: fragment("'{}'::jsonb"),
        null: false,
        comment: "Stores the trial account related information"
    end
  end
end
