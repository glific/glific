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
        default: "monthly",
        comment: "Frequency of billing one of yearly, monthly, quarterly"

      add :finance_poc, :map, comment: "Billing details."

      add :submitter, :map, comment: "Details of the submitter"

      add :signing_authority, :map, comment: "Details of the signing authority."

      add :has_submitted, :boolean,
        default: false,
        comment: "Flag indicating if the registration has been submitted."

      add :has_confirmed, :boolean,
        default: false,
        comment: "Flag indicating if the applicant have confirmed the registration via email"

      add :ip_address, :string, comment: "IP address of the submitter"

      add :terms_agreed, :boolean,
        default: false,
        comment: "Flag indicating if the user agreed or disagreed with the T&C"

      add :support_staff_account, :boolean,
        default: true,
        comment: "Flag indicating if user agrees to create a support staff account"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      add :notion_page_id, :string, comment: "ID of the org's row in notion's onboarding-list database"
      timestamps(type: :utc_datetime)
    end
  end

  defp set_email_non_null do
    alter table(:organizations) do
      modify :email, :string, null: true
    end
  end
end
