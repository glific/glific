defmodule Glific.Repo.Migrations.Extensions do
  use Ecto.Migration

  # This migration assumes the default table name of "fun_with_flags_toggles"
  # is being used. If you have overriden that via configuration, you should
  # change this migration accordingly.

  def up do
    create table(:extensions) do
      # the name to refer the extension
      add :name, :string, null: false

      # the module code as a string, module test as a string, module name, and function name
      add :code, :string, null: false
      # for now, later on we will make test required also
      add :test, :string, null: true
      add :module, :string, null: false
      add :function, :string, null: false

      # check if code is valid and tests have passed
      add :is_valid, :boolean, default: false
      add :is_pass, :boolean, default: false

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
