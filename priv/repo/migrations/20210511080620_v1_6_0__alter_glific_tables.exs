defmodule Glific.Repo.Migrations.V160_AlterGlificTables do
  use Ecto.Migration

  def change do
    notifications()
    flow_editor_type_changes()
  end

  defp notifications do
    alter table(:notifications) do
      add :is_read, :boolean,
        default: false,
        comment: "Has the user read the notifications."
    end
  end

  defp flow_editor_type_changes do
    execute ~s"""
      ALTER TYPE flow_type_enum ADD VALUE IF NOT EXISTS 'messaging';
      """

    alter table(:flows) do
      modify :flow_type,
      :flow_type_enum,
      default: "messaging",
      null: false,
      comment: "Type of flow; default - message"
    end

  end
end
