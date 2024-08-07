defmodule Glific.Jobs.UserJobWorker do
  @moduledoc """
  Worker for processing user jobs.
  """
  require Logger

  alias Glific.{
    Jobs.UserJob,
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
      end
    end)
  end
end
