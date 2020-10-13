defmodule Glific.Repo.Migrations.V0_5_1_AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.5.1 Alter Glific tables
  """

  def change do
    organizations()

    messages()
  end

  defp organizations do
    alter table(:organizations) do
      # add a session limit field to decide length of sessions in minutes
      add :session_limit, :integer, default: 60
    end
  end

  defp messages do
    alter table(:messages) do
      add :session_id, :uuid
    end
  end
end
