defmodule Glific.Contacts.ImportWorker do
  @moduledoc """
  Worker for processing contact chunks.
  """

  require Logger

  use Oban.Worker,
    queue: :default,
    max_attempts: 2,
    priority: 2

  alias Glific.{
    Contacts.Import,
    Jobs.UserJob,
    Repo
  }

  @doc """
  Creating new job for each chunk of contacts.
  """
  @spec make_job(list(), map(), non_neg_integer()) :: :ok
  def make_job(chunk, params, user_job_id) do

    Enum.each(chunk, fn contacts ->
      __MODULE__.new(%{contacts: contacts, params: params, user_job_id: user_job_id})
      |> Oban.insert()
    end)

    :ok
  end

  @doc """
  Standard perform method to use Oban worker.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"contacts" => contacts, "params" => params, "user_job_id" => user_job_id}}) do
    Enum.each(contacts, &process_contact(&1, params))

    Repo.transaction(fn ->
      user_job = Repo.get(UserJob, user_job_id)
      tasks_done = user_job.tasks_done + 1
      Repo.update!(UserJob.changeset(user_job, %{tasks_done: tasks_done}))

      if tasks_done == user_job.total_tasks do
        Repo.update!(UserJob.changeset(user_job, %{status: "success"}))
      end
    end)

    :ok
  end

  defp process_contact(contact, params) do
    user = params["user"]
    contact_attrs = contact
    contact_attrs_with_org = Map.put(contact_attrs, :organization_id, Repo.put_process_state(params["organization_id"]))

    Import.process_data(user, contact_attrs, contact_attrs_with_org)
  end
end
