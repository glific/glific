defmodule Glific.Repo.Migrations.V0_5_2_AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.5.2 Alter Glific tables
  """

  def change do
    flow_contexts()
  end

  defp flow_contexts do
    alter table(:flow_contexts) do
      # add the status field either: "test" or "done"
      add :status, :string, default: "done"
    end
  end
end
