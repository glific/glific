defmodule Glific.TrialAccount.TrialWorker do
  @moduledoc """
  Module for managing trial account lifecycle - expiration reminders and cleanup
  """

  alias Glific.{
    Partners.Organization,
    Repo
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
    end

    :ok
  end

  defp is_trial_org?(organization) do
    not is_nil(organization.trial_expiration_date)
  end

  defp should_cleanup?(organization) do
    is_trial_org?(organization) and
      Date.compare(organization.trial_expiration_date, Date.utc_today()) == :lt
  end
end
