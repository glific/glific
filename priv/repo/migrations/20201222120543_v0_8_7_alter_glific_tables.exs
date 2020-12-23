defmodule Glific.Repo.Migrations.V0_8_7_AlterGlificTables do
  use Ecto.Migration

  def change do
    add_group_id_to_messages()
  end

  defp add_group_id_to_messages() do
    alter table(:messages) do
      # add group_id to record messages sent to a group
      add :group_id, references(:groups, on_delete: :delete_all), null: true
    end
  end
end
