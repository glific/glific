defmodule Glific.Jobs.UserJobWorker do
  @moduledoc """
  Worker for processing user jobs.
  """
  require Logger

  alias Glific.{
    Jobs.UserJob,
    Notifications,
    Repo
  }

  @doc """
  Check and update user job status.
  """
  @spec check_user_job_status(non_neg_integer()) :: :ok
  def check_user_job_status(_org_id) do
    args = %{filter: %{status: "pending", all_tasks_created: true}}
    user_jobs = UserJob.list_user_jobs(args)

    Enum.each(user_jobs, fn user_job ->
      if user_job.total_tasks == user_job.tasks_done do
        user_job
        |> Ecto.Changeset.change(status: "success")
        |> Repo.update!()

        create_completion_notification(user_job)
        Glific.Metrics.increment("Contact upload success")
      end
    end)
  end

  defp create_completion_notification(user_job) do
    Notifications.create_notification(%{
      category: "contact upload",
      message: "Contact upload completed",
      severity: Notifications.types().info,
      organization_id: user_job.organization_id,
      entity: %{user_job_id: user_job.id}
    })
  end
end
