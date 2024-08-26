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

  import Ecto.Query

  @doc """
  Creating new job for each chunk of contacts.
  """
  @spec make_job(list(), map(), non_neg_integer(), non_neg_integer()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def make_job(chunk, params, user_job_id, delay) do
    __MODULE__.new(%{contacts: chunk, params: params, user_job_id: user_job_id},
      schedule_in: delay
    )
    |> Oban.insert()
  end

  @doc """
  Standard perform method to use Oban worker.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"contacts" => contacts, "params" => params, "user_job_id" => user_job_id}
      }) do
    params = %{
      organization_id: params["organization_id"],
      user: %{
        roles: Enum.map(params["user"]["roles"], &String.to_existing_atom/1),
        upload_contacts: params["user"]["upload_contacts"],
        name: params["user"]["name"]
      },
      type: params["type"]
    }

    Repo.put_process_state(params.organization_id)

    validation_errors =
      Enum.reduce(contacts, %{}, fn contact, acc ->
        phone_number = Map.get(contact, "phone")
        errors = validate_phone(phone_number)
        Map.update(acc, :errors, errors, &Map.merge(&1, errors))
      end)

    contacts =
      Enum.map(contacts, fn contact ->
        for {key, value} <- contact, into: %{}, do: {String.to_existing_atom(key), value}
      end)

    errors =
      Enum.reduce(contacts, validation_errors, fn contact, error_map ->
        case process_contact(contact, params) do
          {:ok, _} ->
            error_map

          {:error, error} ->
            Map.update(error_map, :errors, error, &Map.merge(&1, error))
        end
      end)

    Repo.transaction(fn ->
      user_job =
        UserJob
        |> lock("FOR UPDATE")
        |> Repo.get_by(id: user_job_id)

      tasks_done = user_job.tasks_done + 1
      updated_errors = Map.merge(user_job.errors || %{}, errors)
      UserJob.update_user_job(user_job, %{tasks_done: tasks_done, errors: updated_errors})
    end)

    :ok
  end

  @spec validate_phone(String.t() | nil) :: map()
  defp validate_phone(nil) do
    %{"phone" => "Phone number is missing."}
  end

  defp validate_phone(phone) do
    case ExPhoneNumber.parse(phone, "IN") do
      {:ok, _phone} ->
        %{}

      _ ->
        %{phone => "Phone number is not valid."}
    end
  end

  @spec process_contact(map(), map()) :: {:ok, map()} | {:error, map()}
  defp process_contact(contact, params) do
    attrs =
      Map.put(contact, :organization_id, params.organization_id)
      |> Map.put(:type, params.type)

    Import.process_data(params.user, contact, attrs)
  end
end
