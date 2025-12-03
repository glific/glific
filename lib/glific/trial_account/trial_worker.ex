defmodule Glific.TrialAccount.TrialWorker do
  @moduledoc """
  Module for managing trial account lifecycle - expiration reminders and cleanup
  """
  import Ecto.Query

  alias Glific.{
    Erase,
    Partners.Organization,
    Repo,
    Users.User
  }

  require Logger

  @doc """
  Fetches all trial organizations where expiration date has passed
  """
  @spec cleanup_expired_trials() :: :ok
  def cleanup_expired_trials do
    Logger.info("Starting expired trial account cleanup")

    expired_trial_orgs =
      Organization
      |> where([o], o.is_trial_org == true)
      |> where([o], not is_nil(o.trial_expiration_date))
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

    Repo.transaction(
      fn ->
        Erase.delete_organization_data(organization.id)

        update_user_trial_status(organization.id)

        organization
        |> Repo.reload()
        |> Organization.changeset(%{trial_expiration_date: nil})
        |> Repo.update!()
      end,
      timeout: 300_000
    )
    |> case do
      {:ok, _org} ->
        Logger.info("Successfully cleaned up trial organization: #{organization.id}")
        :ok

      {:error, error} ->
        Logger.error("Failed to cleanup trial organization #{organization.id}: #{inspect(error)}")
        {:error, error}
    end
  end

  @spec update_user_trial_status(non_neg_integer) :: :ok
  defp update_user_trial_status(organization_id) do
    {count, _} =
      User
      |> where([u], u.organization_id == ^organization_id)
      |> where([u], u.name not in ["NGO Main Account", "Saas Admin"])
      |> update([u],
        set: [
          trial_metadata: fragment("jsonb_set(trial_metadata, '{status}', '\"expired\"', true)")
        ]
      )
      |> Repo.update_all([])

    Logger.info("Updated #{count} users for organization #{organization_id}")
    :ok
  end
end
