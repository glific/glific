defmodule Glific.TrialAccount.TrialWorker do
  @moduledoc """
  Module for managing trial account lifecycle - expiration, reminders, and cleanup
  """
  import Ecto.Query

  alias Glific.{
    Erase,
    Partners.Organization,
    Repo
  }

  require Logger

  @doc """
  Cleans up all trial organization data where expiration date has passed
  """
  @spec cleanup_expired_trials() :: :ok
  def cleanup_expired_trials do
    Logger.info("Starting expired trial account cleanup")

    expired_trial_orgs =
      Organization
      |> where([o], o.is_trial_org == true)
      |> where([o], o.trial_expiration_date < ^DateTime.utc_now())
      |> Repo.all(skip_organization_id: true)

    Enum.each(expired_trial_orgs, fn org ->
      cleanup_trial_organization(org)
    end)

    Logger.info("Completed expired trial account cleanup")
    :ok
  end

  @spec cleanup_trial_organization(Organization.t()) :: :ok | {:error, any()}
  defp cleanup_trial_organization(organization) do
    Logger.info("Cleaning up expired trial: organization_id: '#{organization.id}'")
    Repo.put_process_state(organization.id)

    case Erase.delete_organization_data(organization.id) do
      :ok ->
        Logger.info("Successfully cleaned up data for trial organization: #{organization.id}")

        organization
        |> Organization.changeset(%{trial_expiration_date: nil})
        |> Repo.update()
        |> case do
          {:ok, _org} ->
            Logger.info(
              "Successfully updated expiration status for trial organization: #{organization.id}"
            )

            :ok

          {:error, error} ->
            Logger.error(
              "Failed to update expiration status for trial organization #{organization.id}: #{inspect(error)}"
            )

            {:error, error}
        end

      {:error, error} ->
        Logger.error("Failed to cleanup trial organization #{organization.id}: #{inspect(error)}")
        {:error, error}
    end
  end
end
