defmodule Glific.Repo.Migrations.AddSaasTable do
  use Ecto.Migration

  def change do
    saas_table()

    organizations()
  end

  defp organizations do
    alter table(:organizations) do
      add :is_approved, :boolean,
        default: false,
        comment: "Manual approval of an organization to trigger onboarding workflow"
    end
  end

  defp saas_table do
    create table(:saas,
             prefix: @global_schema,
             comment:
               "Lets store all the meta data we need to drive the SaaS platform in this table"
           ) do
      add :organization_id, references(:organizations, on_delete: :delete_all),
        comment: "The master organization running this service"

      add :saas_phone, :string, comment: "Phone number for the SaaS admin account"

      add :stripe_ids, :jsonb,
        default: "[]",
        comment: "All the stripe subscriptions IDS, no more config"

      timestamps(type: :utc_datetime)
    end
  end
end
