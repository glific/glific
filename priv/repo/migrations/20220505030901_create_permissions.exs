defmodule Glific.Repo.Migrations.CreatePermissions do
  use Ecto.Migration
  @global_schema Application.fetch_env!(:glific, :global_schema)

  def change do
    create table(:permissions, prefix: @global_schema) do
      add :entity, :string

      timestamps()
    end
  end
end
