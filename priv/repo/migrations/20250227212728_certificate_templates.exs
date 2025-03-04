defmodule Glific.Repo.Migrations.CertificateTemplates do
  use Ecto.Migration

  def change do
    Glific.Enums.CertificateTemplateType.create_type()
    create_certificate_template()
    create_issued_certfifcates()
  end

  @spec create_certificate_template() :: any()
  defp create_certificate_template() do
    create table(:certificate_templates) do
      add :label, :string, null: false, comment: "Title of the certificate template"
      add :url, :string, null: false, comment: "Url of the certificate template"
      add :description, :text, comment: "Details about the certificate template"

      add :type, Glific.Enums.CertificateTemplateType.type(),
        default: "slides",
        comment: "Format of template used for ex: slides, pdf etc.."

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      timestamps(type: :utc_datetime)
    end

    create unique_index(:certificate_templates, [:label, :organization_id])
  end

  defp create_issued_certfifcates do
    create table(:issued_certificates) do
      # we doing cascade delete, since we sync these tables to BQ, so will be available for tracking
      add :certificate_template_id, references(:certificate_templates, on_delete: :delete_all),
        null: false,
        comment: "Unique certificate template ID"

      add :contact_id, references(:contacts, on_delete: :delete_all),
        null: false,
        comment: "Unique contact ID"

      add :gcs_url, :string, comment: "GCS url of the final generated certificate"

      add :errors, :map, default: %{}, comment: "Errors during certificate generation"

      add :status, :string,
        comment:
          "Incremental status while certificate generation, available options are: copied_to_drive, replaced_text, thumbnail_created, gcs_uploaded"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      timestamps(type: :utc_datetime)
    end
  end
end
