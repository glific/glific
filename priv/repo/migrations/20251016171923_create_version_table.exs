defmodule Glific.Repo.Migrations.AddVersions do
  use Ecto.Migration

  def change do
    create table(:versions) do
      add :patch, :binary, comment: "The patch in Erlang External Term Format"

      add :entity_id, :integer

      add :entity_schema, :string, comment: "name of the table the entity is in"

      add :action, :string,
        comment: "type of the action that has happened to the entity (created, updated, deleted)"

      add :recorded_at, :utc_datetime, comment: "when has this happened"

      add :rollback, :boolean, default: false, comment: "was this change part of a rollback?"

      add :user_id, references(:users, on_update: :update_all, on_delete: :nilify_all)
    end

    create index(:versions, [:entity_schema, :entity_id])
  end
end
