defmodule Glific.Repo.Migrations.AddRegistrationTable do
  use Ecto.Migration

  def change do
    set_email_non_null()
    create_registrations()
  end

  defp create_registrations do
    create table(:registrations) do
      add :org_details, :map, comment: "Details about the organization."

      add :platform_details, :map, comment: "Details about the Gupshup platform."

      add :billing_frequency, :string,
        default: "yearly",
        comment: "Frequency of billing one of yearly, monthly, quaeterly"

      add :finance_poc, :map, comment: "Billing details."

      add :submitter, :map, comment: "Details of the submitter"

      add :signing_authority, :map, comment: "Details of the signing authority."

      add :has_submitted, :boolean,
        default: false,
        comment: "Flag indicating if the registration has been submitted."

      add :has_confirmed, :boolean,
        default: false,
        comment: "Flag indicating if the applicant have confirmed the registration via email"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      timestamps(type: :utc_datetime)
    end
  end

  defp set_email_non_null do
    alter table(:organizations) do
      modify :email, :string, null: true
    end
  end
end
