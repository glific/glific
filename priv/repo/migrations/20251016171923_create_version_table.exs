defmodule Glific.Repo.Migrations.AddVersions do
  use Ecto.Migration

  def change do
    create table(:versions) do
      add :patch, :binary, null: false, comment: "The patch in Erlang External Term Format"

      add :entity_id, :integer, null: false

      add :entity_schema, :string, null: false, comment: "name of the table the entity is in"

      add :action, :string,
        null: false,
        comment: "type of the action that has happened to the entity (created, updated, deleted)"

      add :recorded_at, :utc_datetime, null: false, comment: "when has this happened"

      add :rollback, :boolean,
        null: false,
        default: false,
        comment: "was this change part of a rollback?"

      add :user_id, references(:users, on_update: :update_all, on_delete: :nilify_all)

      add :organization_id, references(:organizations, on_delete: :nilify_all),
        null: true,
        comment: "Unique organization ID."
    end

    create index(:versions, [:entity_schema, :entity_id])
    create index(:versions, [:organization_id])
  end
end
