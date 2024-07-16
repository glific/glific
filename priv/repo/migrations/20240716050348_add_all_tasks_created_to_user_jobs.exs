defmodule Glific.Repo.Migrations.AddAllTasksCreatedToUserJobs do
  use Ecto.Migration

  def change do
    alter table(:user_jobs) do
      add :all_tasks_created, :boolean, default: false, null: false
    end
  end
end
