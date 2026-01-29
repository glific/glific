defmodule Glific.TrialAccount.TrialWorker do
  @moduledoc """
  Module for managing trial account lifecycle - expiration, reminders, and cleanup
  """
  import Ecto.Query

  alias Glific.{
    Communications.Mailer,
    Erase,
    Mails.TrialAccountMail,
    Partners.Organization,
    Repo,
    TrialUsers,
    Users.User
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

    with :ok <- Erase.delete_organization_data(organization.id),
         {:ok, _org} <-
           organization
           |> Organization.changeset(%{trial_expiration_date: nil})
           |> Repo.update() do
      Logger.info("Successfully cleaned up and reset trial organization: #{organization.id}")
      :ok
    else
      {:error, error} ->
        Logger.error("Failed to process trial organization #{organization.id}: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Sends day 3 follow-up emails to trial users who started their trial 3 days ago
  """
  @spec send_day_3_followup_emails() :: :ok
  def send_day_3_followup_emails do
    Logger.info("Starting day 3 follow-up email task")

    # Day 3 of a 14-day trial = 11 days remaining
    11
    |> fetch_trial_orgs_by_days_remaining()
    |> Enum.each(&send_day_3_email_to_org/1)

    Logger.info("Completed day 3 follow-up email task")
    :ok
  end

  @doc """
  Sends day 6 follow-up emails to trial users who started their trial 6 days ago
  """
  @spec send_day_6_followup_emails() :: :ok
  def send_day_6_followup_emails do
    Logger.info("Starting day 6 follow-up email task")

    # Day 6 of a 14-day trial = 8 days remaining
    8
    |> fetch_trial_orgs_by_days_remaining()
    |> Enum.each(&send_day_6_email_to_org/1)

    Logger.info("Completed day 6 follow-up email task")
    :ok
  end

  @doc """
  Sends day 12 follow-up emails to trial users who started their trial 12 days ago
  """
  @spec send_day_12_followup_emails() :: :ok
  def send_day_12_followup_emails do
    Logger.info("Starting day 12 follow-up email task")

    # Day 12 of a 14-day trial = 2 days remaining
    2
    |> fetch_trial_orgs_by_days_remaining()
    |> Enum.each(&send_day_12_email_to_org/1)

    Logger.info("Completed day 12 follow-up email task")
    :ok
  end

  @doc """
  Sends day 14 follow-up emails to trial users on their last day of trial
  """
  @spec send_day_14_followup_emails() :: :ok
  def send_day_14_followup_emails do
    Logger.info("Starting day 14 follow-up email task")

    # Day 14 of a 14-day trial = 0 days remaining (expires today)
    0
    |> fetch_trial_orgs_by_days_remaining()
    |> Enum.each(&send_day_14_email_to_org/1)

    Logger.info("Completed day 14 follow-up email task")
    :ok
  end

  @spec send_day_3_email_to_org(Organization.t()) :: :ok
  defp send_day_3_email_to_org(%{id: organization_id} = organization) do
    organization_id
    |> fetch_trial_user()
    |> case do
      nil ->
        Logger.warning(
          "No admin or trial user found for trial organization #{organization_id}, skipping day 3 email"
        )

      trial_user ->
        Logger.info(
          "Sending day 3 follow-up email to #{trial_user.email} for organization #{organization_id}"
        )

        organization
        |> TrialAccountMail.day_3_followup(trial_user)
        |> Mailer.send(%{
          category: "trial_day_3_followup",
          organization_id: organization.id
        })
    end

    :ok
  end

  @spec send_day_6_email_to_org(Organization.t()) :: :ok
  defp send_day_6_email_to_org(%{id: organization_id} = organization) do
    organization_id
    |> fetch_trial_user()
    |> case do
      nil ->
        Logger.warning(
          "No admin or trial user found for trial organization #{organization_id}, skipping day 6 email"
        )

      trial_user ->
        Logger.info(
          "Sending day 6 follow-up email to #{trial_user.email} for organization #{organization_id}"
        )

        organization
        |> TrialAccountMail.day_6_followup(trial_user)
        |> Mailer.send(%{
          category: "trial_day_6_followup",
          organization_id: organization.id
        })
    end

    :ok
  end

  @spec send_day_12_email_to_org(Organization.t()) :: :ok
  defp send_day_12_email_to_org(%{id: organization_id} = organization) do
    organization_id
    |> fetch_trial_user()
    |> case do
      nil ->
        Logger.warning(
          "No admin or trial user found for trial organization #{organization_id}, skipping day 12 email"
        )

      trial_user ->
        Logger.info(
          "Sending day 12 follow-up email to #{trial_user.email} for organization #{organization_id}"
        )

        organization
        |> TrialAccountMail.day_12_followup(trial_user)
        |> Mailer.send(%{
          category: "trial_day_12_followup",
          organization_id: organization.id
        })
    end

    :ok
  end

  @spec send_day_14_email_to_org(Organization.t()) :: :ok
  defp send_day_14_email_to_org(%{id: organization_id} = organization) do
    organization_id
    |> fetch_trial_user()
    |> case do
      nil ->
        Logger.warning(
          "No admin or trial user found for trial organization #{organization_id}, skipping day 14 email"
        )

      trial_user ->
        Logger.info(
          "Sending day 14 follow-up email to #{trial_user.email} for organization #{organization_id}"
        )

        organization
        |> TrialAccountMail.day_14_followup(trial_user)
        |> Mailer.send(%{
          category: "trial_day_14_followup",
          organization_id: organization.id
        })
    end

    :ok
  end

  @spec fetch_trial_user(integer()) :: TrialUsers.t() | nil
  defp fetch_trial_user(organization_id) do
    from(u in User,
      join: t in TrialUsers,
      on: u.phone == t.phone,
      where: u.organization_id == ^organization_id,
      where: "admin" in u.roles,
      order_by: [asc: u.id],
      limit: 1,
      select: t
    )
    |> Repo.one(skip_organization_id: true)
  end

  # Fetches trial organizations that have a specific number of days remaining until expiration.
  @spec fetch_trial_orgs_by_days_remaining(integer()) :: [Organization.t()]
  defp fetch_trial_orgs_by_days_remaining(days_remaining) do
    now = DateTime.utc_now()
    start_range = DateTime.add(now, days_remaining, :day)
    end_range = DateTime.add(now, days_remaining + 1, :day)

    Organization
    |> where([o], o.is_trial_org == true)
    |> where([o], not is_nil(o.trial_expiration_date))
    |> where([o], o.trial_expiration_date >= ^start_range)
    |> where([o], o.trial_expiration_date < ^end_range)
    |> Repo.all(skip_organization_id: true)
  end
end
