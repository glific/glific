defmodule Glific.Contacts.ImportWorker do
  @moduledoc """
  Worker for processing contact chunks one field at a time.

  Superseded by `Glific.Contacts.BulkImportWorker`, which batches its writes. Nothing
  enqueues this worker any more; it is kept only so that jobs already sitting in the
  queue can still drain, and should be removed once they have.
  """
  require Logger

  use Oban.Worker,
    queue: :contact_import,
    max_attempts: 2,
    priority: 1

  alias Glific.{
    Contacts.Import,
    Repo
  }

  @doc """
  Standard perform method to use Oban worker.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"contacts" => contacts, "params" => params, "user_job_id" => user_job_id}
      }) do
    params = Import.parse_worker_params(params, params["organization_id"])

    Repo.put_process_state(params.organization_id)

    {validation_errors, valid_contacts} = Import.validate_contacts(contacts)

    contacts =
      Enum.map(valid_contacts, fn contact ->
        for {key, value} <- contact, into: %{}, do: {String.to_existing_atom(key), value}
      end)

    contacts
    |> Enum.reduce(validation_errors, fn contact, error_map ->
      case process_contact(contact, params) do
        {:ok, _} -> error_map
        {:error, error} -> Map.merge(error_map, error)
      end
    end)
    |> then(&Import.update_user_job_progress(user_job_id, &1))
  end

  @spec process_contact(map(), map()) :: {:ok, map()} | {:error, map()}
  defp process_contact(contact, params) do
    attrs =
      Map.put(contact, :organization_id, params.organization_id)
      |> Map.put(:type, params.type)

    Import.process_data(params.user, contact, attrs)
  end
end
