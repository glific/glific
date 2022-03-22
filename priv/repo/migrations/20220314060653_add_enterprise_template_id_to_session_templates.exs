defmodule Glific.Repo.Migrations.AddEnterpriseTemplateIdToSessionTemplates do
  use Ecto.Migration

  def change do
    bsp_id()
  end

  defp bsp_id do
    alter table(:session_templates) do
      add :bsp_id, :string
    end
  end
end
