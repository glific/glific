defmodule Glific.Repo.Migrations.V1_5_0_AlterGlificTables do
  @moduledoc false
  use Ecto.Migration

  def change do
    organizations()

    chatbase_jobs()
  end

  defp organizations do
    drop_if_exists unique_index(:organizations, :email)
  end

  defp chatbase_jobs do
    drop_if_exists table(:chatbase_jobs)
  end
end
