defmodule MyApp.Repo.Migrations.UpdateObanJobsToV10 do
  use Ecto.Migration

  def change do
    # do nothing, we had made an error in our previous migration
    # and forgot to include the global prefix
    # the new migration in in the upgrade_oban_jobs_to_v10_1
  end
end
