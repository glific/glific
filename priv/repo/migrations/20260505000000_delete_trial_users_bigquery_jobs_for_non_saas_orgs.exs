defmodule Glific.Repo.Migrations.DeleteTrialUsersBigqueryJobsForNonSaasOrgs do
  use Ecto.Migration

  def up do
    execute("""
    DELETE FROM bigquery_jobs
    WHERE "table" = 'trial_users'
      AND organization_id NOT IN (
        SELECT organization_id FROM saas WHERE name = 'Tides'
      )
    """)
  end

  def down, do: :ok
end
