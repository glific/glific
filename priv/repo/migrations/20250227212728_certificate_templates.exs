defmodule Glific.Repo.Migrations.CertificateTemplates do
  use Ecto.Migration

  def change do
    create table(:certificate_templates) do
      add :label, :string, null: false, comment: "Title of the certificate template"
      add :url, :string, null: false, comment: "Url of the certificate template"
      add :description, :text, comment: "Details about the certificate template"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      timestamps(type: :utc_datetime)
    end

    create unique_index(:certificate_templates, [:label, :organization_id])
  end
end
