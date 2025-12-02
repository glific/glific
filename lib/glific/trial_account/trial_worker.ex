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
  Cleanup expired trials - called daily
  Removes all data except user records
  """
  @spec cleanup_expired_trials(non_neg_integer) :: :ok
  def cleanup_expired_trials(organization_id) do
    organization = Repo.get!(Organization, organization_id)

    if should_cleanup?(organization) do
      Logger.info("Cleaning up expired trial: organization_id: '#{organization_id}'")
      Erase.delete_organization_data(organization_id)

      # Reset org for reallocation
      organization
      |> Organization.changeset(%{trial_expiration_date: nil})
      |> Repo.update()

      update_user_trial_status(organization.id)
    end

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
      |> User.changeset(%{trial_metadata: updated_metadata})
      |> Repo.update()
    end)

    Logger.info(
      "Updated #{length(users)} user(s) trial status to expired for org #{organization_id}"
    )
  end

  @spec is_trial_org?(Organization.t()) :: boolean()
  defp is_trial_org?(organization) do
    not is_nil(organization.trial_expiration_date)
  end

  @spec should_cleanup?(Organization.t()) :: boolean()
  defp should_cleanup?(organization) do
    is_trial_org?(organization) and
      Date.compare(organization.trial_expiration_date, Date.utc_today()) == :lt
  end
end
