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
      # add the status field either: "test" or "published"
      add :status, :string, default: "published"
    end
  end
end
