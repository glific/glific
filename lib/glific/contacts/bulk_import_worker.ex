defmodule Glific.Contacts.BulkImportWorker do
  @moduledoc """
  Worker for processing contact chunks with batched writes.

  Replaces the per-field write path in `Glific.Contacts.ImportWorker`, which issued six to
  nine statements per field per contact. `organization_id` is a top-level job arg so the
  `contact_import` queue can partition its global limit on it.
  """
  use Oban.Worker,
    queue: :contact_import,
    max_attempts: 2,
    priority: 1

  alias Glific.{
    Contacts.BulkImport,
    Contacts.Import,
    Repo
  }

  @chunk_failed "Import failed for this batch, please retry these rows"

  @doc """
  Creating new job for each chunk of contacts.
  """
  @spec make_job(list(), map(), non_neg_integer(), non_neg_integer()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def make_job(chunk, params, user_job_id, delay) do
    __MODULE__.new(
      %{
        contacts: chunk,
        params: params,
        user_job_id: user_job_id,
        organization_id: params.organization_id
      },
      schedule_in: delay
    )
    |> Oban.insert()
  end

  @doc """
  Standard perform method to use Oban worker.
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(
        %Oban.Job{
          args: %{
            "contacts" => contacts,
            "params" => params,
            "user_job_id" => user_job_id,
            "organization_id" => organization_id
          }
        } = job
      ) do
    Repo.put_process_state(organization_id)

    contacts
    |> BulkImport.process_chunk(Import.parse_worker_params(params, organization_id))
    |> then(&Import.update_user_job_progress(user_job_id, &1))
  rescue
    exception ->
      handle_failure(exception, __STACKTRACE__, job, contacts, user_job_id)
  end

  @spec handle_failure(Exception.t(), Exception.stacktrace(), Oban.Job.t(), [map()], integer()) ::
          :ok | no_return()
  defp handle_failure(exception, stacktrace, job, contacts, user_job_id) do
    if job.attempt < job.max_attempts do
      reraise exception, stacktrace
    else
      Glific.log_exception(exception)

      contacts
      |> Map.new(&{&1["phone"] || "unknown", @chunk_failed})
      |> then(&Import.update_user_job_progress(user_job_id, &1))
    end
  end
end
