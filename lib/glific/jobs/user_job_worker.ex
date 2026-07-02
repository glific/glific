defmodule Glific.Jobs.UserJobWorker do
  @moduledoc """
  Worker for processing user jobs.
  """
  require Logger

  alias Glific.{
    Groups.CollectionPrimaryPhone,
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
        Glific.Metrics.increment(success_metric(user_job.type))
      end
    end)
  end

  @spec success_metric(String.t() | nil) :: String.t()
  defp success_metric(type) do
    if type == CollectionPrimaryPhone.job_type(),
      do: "Collection primary phone success",
      else: "Contact upload success"
  end

  defp create_completion_notification(user_job) do
    {category, message} = completion_details(user_job.type)

    Notifications.create_notification(%{
      category: category,
      message: message,
      severity: Notifications.types().info,
      organization_id: user_job.organization_id,
      entity: %{user_job_id: user_job.id}
    })
  end

  # The category + message shown to the admin when a job completes, per job type.
  @spec completion_details(String.t() | nil) :: {String.t(), String.t()}
  defp completion_details(type) do
    if type == CollectionPrimaryPhone.job_type() do
      {"Collection Primary Phone",
       "Setting the primary phone across the collection has completed."}
    else
      {"Contact Upload", "Contact upload completed"}
    end
  end
end
