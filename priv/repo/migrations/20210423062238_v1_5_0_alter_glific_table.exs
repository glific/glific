defmodule Glific.Repo.Migrations.V1_5_0_AlterGlificTables do
  @moduledoc false
  use Ecto.Migration

  def change do
    organizations()
  end

  defp organizations do
    drop_if_exists unique_index(:organizations, :email)
  end
end
