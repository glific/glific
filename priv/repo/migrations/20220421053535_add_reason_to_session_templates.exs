defmodule Glific.Repo.Migrations.AddReasonToSessionTemplates do
  use Ecto.Migration

  def change do
    alter table(:session_templates) do
      add :reason, :string, comment: "reason for template being rejected"
    end
  end
end
