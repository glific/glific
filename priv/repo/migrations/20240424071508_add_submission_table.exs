defmodule Glific.Repo.Migrations.AddSubmissionTable do
  use Ecto.Migration

  def change do
    create table(:submissions) do
      add :org_details, :map, null: false, comment: "Details about the organization."

      add :platform_details, :map, null: false, comment: "Details about the Gupshup platform."

      add :billing_frequency, :string,
        default: "yearly",
        comment: "Frequency of billing one of yearly, monthly, quaeterly"

      add :finance_poc, :map, null: false, comment: "Billing details."

      add :submitter, :map, null: false, comment: "Details of the submitter"

      add :signing_authority, :map, null: false, comment: "Details of the signing authority."

      add :has_submitted, :boolean,
        default: false,
        comment: "Flag indicating if the application has been submitted sucessfully or not."

      add :has_confirmed, :boolean,
        default: false,
        comment: "Flag indicating if the applicant have confirmed the submission via email"

      # Foreign key to organization, restricting the scope of this table to the specified organization.
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: true,
        comment: "Unique organization ID."

      timestamps(type: :utc_datetime)
    end
  end
end
