defmodule Glific.Repo.Migrations.V0_11_6_AlterGlificTables do
  @moduledoc """
  Updating glific tables
  """
  use Ecto.Migration

  def change do
    chatbase_jobs()
  end

  defp chatbase_jobs do
    alter table(:chatbase_jobs) do
      modify :message_id, :integer, default: 0
    end
  end
end
