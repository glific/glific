defmodule Glific.Repo.Migrations.V0_8_4_AlterGlificTables do
  use Ecto.Migration

  def change do
    add_hsm_status_to_session_templates()
  end

  defp add_hsm_status_to_session_templates() do
    alter table(:session_templates) do
      # whatsapp status of hsm template
      add :status, :string, null: true
    end
  end
end
