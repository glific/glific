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
      }
    }

    Repo.put_process_state(params.organization_id)

    {errors, _} =
      Enum.reduce(contacts, {%{}, 0}, fn contact, {acc, index} ->
        phone_number = Map.get(contact, "phone")
        errors = validate_phone(phone_number)
        acc = Map.update(acc, :errors, errors, &Map.merge(&1, errors))
        {acc, index + 1}
      end)

    contacts =
      Enum.map(contacts, fn contact ->
        for {key, value} <- contact, into: %{}, do: {String.to_existing_atom(key), value}
      end)

    errors =
      Enum.reduce(contacts, errors, fn contact, error_map ->
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
    user = params.user
    contact_attrs = contact

    contact_attrs_with_org =
      Map.put(contact_attrs, :organization_id, Repo.put_process_state(params.organization_id))

    Import.process_data(user, contact_attrs, contact_attrs_with_org)
  end
end
