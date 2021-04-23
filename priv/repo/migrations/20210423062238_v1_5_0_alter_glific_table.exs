defmodule Glific.Repo.Migrations.V1_5_0_AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.5.0 Alter Glific tables
  """
  @global_schema Application.fetch_env!(:glific, :global_schema)

  def change do
    organizations()
  end

  defp organizations do
    drop_if_exists unique_index(:organizations, :email)
  end
end
