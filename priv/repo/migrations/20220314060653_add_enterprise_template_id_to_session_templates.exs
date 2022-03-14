defmodule Glific.Repo.Migrations.AddEnterpriseTemplateIdToSessionTemplates do
  use Ecto.Migration

  def change do
    enterprise_template_id()
  end

  defp enterprise_template_id do
    alter table(:session_templates) do
      add :enterprise_template_id, :string
    end
  end
end
