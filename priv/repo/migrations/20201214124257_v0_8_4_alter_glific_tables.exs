defmodule Glific.Repo.Migrations.V0_8_4_AlterGlificTables do
  use Ecto.Migration

  def change do
    add_hsm_data_to_session_templates()
  end

  defp add_hsm_data_to_session_templates() do
    alter table(:session_templates) do
      # whatsapp status of hsm template
      add :status, :string, null: true, comment: "Whatsapp status of the HSM template"

      # whatsapp hsm category
      add :category, :string, null: true, comment: "Whatsapp HSM category"

      # hsm example with params
      add :example, :string, null: true, comment: "HSM example with parameters"
    end
  end
end
