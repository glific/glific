defmodule Glific.Jobs.UserJobWorker do
  @moduledoc """
  Worker for processing user jobs.
  """
  require Logger

  alias Glific.{
    Repo,
    Jobs.UserJob
  }

  @doc """
  Check and update user job status.
  """
  def check_user_job_status(_org_id) do
    args = %{status: "pending", all_tasks_created: true}

    user_jobs = UserJob.list_user_jobs(args)


    Enum.each(user_jobs, fn user_job ->
      if user_job.total_tasks == user_job.tasks_done do
        Repo.transaction(fn ->
          user_job = Ecto.Changeset.change(user_job, status: "success")
          Repo.update!(user_job)
        end)
      end
    end)
  end

  # Other functions related to UserJobWorker
end
