defmodule Glific.Contacts.ImportWorker do
  @moduledoc """
  Worker for processing contact chunks.
  """
  require Logger

  use Oban.Worker,
    queue: :contact_import,
    max_attempts: 2,
    priority: 1

  alias Glific.{
    Contacts,
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

    {validation_errors, valid_contacts} =
      Enum.reduce(contacts, {%{}, []}, fn contact, {acc, valid_contacts} ->
        case validate_contact(contact) do
          errors when errors == %{} ->
            {acc, [contact | valid_contacts]}

          errors ->
            {Map.update(acc, :errors, errors, &Map.merge(&1, errors)), valid_contacts}
        end
      end)

    contacts =
      Enum.map(valid_contacts, fn contact ->
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

  @spec validate_contact(map()) :: map()
  defp validate_contact(%{"phone" => phone}) when phone in [nil, ""] do
    %{"phone" => "Phone number is missing."}
  end

  defp validate_contact(%{"phone" => phone, "name" => name}) do
    case Contacts.parse_phone_number(phone) do
      {:ok, phone} ->
        validate_name(name, phone)

      {:error, message} ->
        %{phone => message}
    end
  end

  defp validate_contact(_), do: %{"error" => "Failed to parse some rows"}

  @spec validate_name(String.t(), String.t()) :: map()
  defp validate_name(name, phone) when name in [nil, ""] do
    %{phone => "Contact name is empty"}
  end

  defp validate_name(_name, _phone), do: %{}

  @spec process_contact(map(), map()) :: {:ok, map()} | {:error, map()}
  defp process_contact(contact, params) do
    attrs =
      Map.put(contact, :organization_id, params.organization_id)
      |> Map.put(:type, params.type)

    Import.process_data(params.user, contact, attrs)
  end
end
