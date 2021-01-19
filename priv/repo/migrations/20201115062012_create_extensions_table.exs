defmodule Glific.Repo.Migrations.Extensions do
  use Ecto.Migration

  # This migration assumes the default table name of "fun_with_flags_toggles"
  # is being used. If you have overriden that via configuration, you should
  # change this migration accordingly.

  def up do
    create table(:extensions) do
      # the name to refer the extension
      add :name, :string, null: false

      add :module, :string, null: false
      add :condition, :string, null: false
      add :action, :string, null: false
      add :args, {:array, :string}, default: []

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:extensions, [:name, :organization_id])
  end

  def down do
    drop table(:extensions)
  end
end
