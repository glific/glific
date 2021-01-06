defmodule Glific.Repo.Migrations.V0_9_2_AlterGlificTables do
  use Ecto.Migration

  def change do
    organizations()

    messages()
  end

  defp organizations() do
    alter table(:organizations) do
      add :last_communication_at, :utc_datetime
    end
  end

  defp messages() do
    alter table(:messages) do
      modify :bsp_message_id, :text
    end
  end
end
