defmodule Glific.Repo.Migrations.AddStatusEnumToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :trial_metadata, :map,
        default: fragment("'{\"status\": \"active\"}'::jsonb"),
        null: false,
        comment: "Indicates whether the user account is active or expired"
    end
  end
end
