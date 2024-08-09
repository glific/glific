defmodule Glific.Repo.Migrations.CreateUserJobs do
  use Ecto.Migration

  def change do
    create table(:user_jobs) do
      add :status, :string, default: "pending", comment: "Job status: failed/pending/success"

      add :type, :string, comment: "Type of job, e.g., contact_import"

      add :total_tasks, :integer, comment: "Total number of tasks for this job"

      add :tasks_done, :integer, comment: "Number of tasks completed for this job"

      add :all_tasks_created, :boolean,
        default: false,
        comment: "Specifies whether all tasks created"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      add :errors, :map,
        default: %{},
        comment: "Details of any errors that occurred during the job"

      timestamps(type: :utc_datetime)
    end
  end
end
