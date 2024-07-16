defmodule Glific.Contacts.ImportWorker do
  @moduledoc """
  Worker for processing contact chunks.
  """
  import Ecto.Query

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
    __MODULE__.new(%{contacts: chunk, params: params, user_job_id: user_job_id})
    |> Oban.insert()
  end

  @doc """
  Standard perform method to use Oban worker.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"contacts" => contacts, "params" => params, "user_job_id" => user_job_id} = args
      }) do

    Repo.put_process_state(params["organization_id"])
    result = Enum.reduce_while(contacts, %{}, fn contact, acc ->
      phone_number = Map.get(contact, "phone")
      acc = validate_phone(acc, phone_number)

      if Map.has_key?(acc, :errors) do
        {:halt, acc}
      else
        {:cont, acc}
      end
    end)

    if Map.has_key?(result, :errors) do
      {:error, result}
    else
      user_job = Repo.get(UserJob, user_job_id)
      tasks_done = user_job.tasks_done + 1
      Repo.update!(UserJob.changeset(user_job, %{tasks_done: tasks_done}))
    # Enum.each(contacts, fn contact ->
    #   process_contact(contact, params)
    # end)
    end

    :ok
  end

  @spec validate_phone(map(), String.t(), atom()) :: map()
  defp validate_phone(result, phone, key \\ :phone) do
    case ExPhoneNumber.parse(phone, "IN") do
      {:ok, _phone} ->
        result

      _ ->
        Map.update(result, :errors, %{key => "Phone is not valid."}, &Map.put(&1, key, "Phone is not valid."))
    end
  end

  defp process_contact(contact, params) do
    user = params["user"]
    contact_attrs = contact

    contact_attrs_with_org =
      Map.put(contact_attrs, :organization_id, Repo.put_process_state(params["organization_id"]))
    Import.process_data(user, contact_attrs, contact_attrs_with_org)
  end

  def check_user_job_status(_org_id) do
    query =
      from uj in UserJob,
        where: uj.status == "pending" and uj.all_tasks_created == true

    user_jobs = Repo.all(query)

    Enum.each(user_jobs, fn user_job ->
      if user_job.total_tasks == user_job.tasks_done do
        Repo.transaction(fn ->
          user_job = Ecto.Changeset.change(user_job, status: "success")
          Repo.update!(user_job)
        end)
      end
    end)
  end
end
