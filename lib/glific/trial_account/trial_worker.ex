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
      |> where([o], o.is_trial == true)
      |> where([o], not is_nil(o.trial_expiration_date))
      |> where([o], o.trial_expiration_date < ^DateTime.utc_now())
      |> Repo.all(skip_organization_id: true)

    Enum.each(expired_trial_orgs, fn org ->
      cleanup_trial_organization(org)
    end)

    Logger.info("Completed expired trial account cleanup")
    :ok
  end

  @spec cleanup_trial_organization(Organization.t()) :: :ok
  defp cleanup_trial_organization(organization) do
    Logger.info("Cleaning up expired trial: organization_id: '#{organization.id}'")

    Repo.put_process_state(organization.id)

    Erase.delete_organization_data(organization.id)

    update_user_trial_status(organization.id)

    # Reload and reset org for reallocation
    organization = Repo.get!(Organization, organization.id)

    {:ok, _org} =
      organization
      |> Organization.changeset(%{trial_expiration_date: nil})
      |> Repo.update()

    Logger.info("Successfully cleaned up trial organization: #{organization.id}")
    :ok
  end

  @spec update_user_trial_status(non_neg_integer) :: :ok
  defp update_user_trial_status(organization_id) do
    users =
      User
      |> where([u], u.organization_id == ^organization_id)
      |> where([u], u.name not in ["NGO Main Account", "Saas Admin"])
      |> Repo.all()

    Enum.each(users, fn user ->
      updated_metadata =
        user.trial_metadata
        |> Map.put("status", "expired")

      user
      |> Ecto.Changeset.change(%{trial_metadata: updated_metadata})
      |> Repo.update()
    end)

    :ok
  end
end
