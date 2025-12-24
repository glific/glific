defmodule Glific.TrialAccount.TrialWorker do
  @moduledoc """
  Module for managing trial account lifecycle - expiration, reminders, and cleanup
  """
  import Ecto.Query

  alias Glific.{
    Communications.Mailer,
    Erase,
    Mails.MailLog,
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

    # Calculate the date range for trials that started 3 days ago
    # Since trial is 14 days, day 3 means 11 days remaining
    # We check for trials expiring in 11-12 days to catch the day 3 window
    now = DateTime.utc_now()
    eleven_days = DateTime.add(now, 11, :day)
    twelve_days = DateTime.add(now, 12, :day)

    day_3_trial_orgs =
      Organization
      |> where([o], o.is_trial_org == true)
      |> where([o], not is_nil(o.trial_expiration_date))
      |> where([o], o.trial_expiration_date >= ^eleven_days)
      |> where([o], o.trial_expiration_date < ^twelve_days)
      |> Repo.all(skip_organization_id: true)

    Enum.each(day_3_trial_orgs, fn org ->
      send_day_3_email_to_org(org)
    end)

    Logger.info("Completed day 3 follow-up email task")
    :ok
  end

  @doc """
  Sends day 6 follow-up emails to trial users who started their trial 6 days ago
  """
  @spec send_day_6_followup_emails() :: :ok
  def send_day_6_followup_emails do
    Logger.info("Starting day 6 follow-up email task")

    # Calculate the date range for trials that started 6 days ago
    # Since trial is 14 days, day 6 means 8 days remaining
    # We check for trials expiring in 8-9 days to catch the day 6 window
    now = DateTime.utc_now()
    eight_days = DateTime.add(now, 8, :day)
    nine_days = DateTime.add(now, 9, :day)

    day_6_trial_orgs =
      Organization
      |> where([o], o.is_trial_org == true)
      |> where([o], not is_nil(o.trial_expiration_date))
      |> where([o], o.trial_expiration_date >= ^eight_days)
      |> where([o], o.trial_expiration_date < ^nine_days)
      |> Repo.all(skip_organization_id: true)

    Enum.each(day_6_trial_orgs, fn org ->
      send_day_6_email_to_org(org)
    end)

    Logger.info("Completed day 6 follow-up email task")
    :ok
  end

  @doc """
  Sends day 12 follow-up emails to trial users who started their trial 12 days ago
  """
  @spec send_day_12_followup_emails() :: :ok
  def send_day_12_followup_emails do
    Logger.info("Starting day 12 follow-up email task")

    # Calculate the date range for trials that started 12 days ago
    # Since trial is 14 days, day 12 means 2 days remaining
    # We check for trials expiring in 2-3 days to catch the day 12 window
    now = DateTime.utc_now()
    two_days = DateTime.add(now, 2, :day)
    three_days = DateTime.add(now, 3, :day)

    day_12_trial_orgs =
      Organization
      |> where([o], o.is_trial_org == true)
      |> where([o], not is_nil(o.trial_expiration_date))
      |> where([o], o.trial_expiration_date >= ^two_days)
      |> where([o], o.trial_expiration_date < ^three_days)
      |> Repo.all(skip_organization_id: true)

    Enum.each(day_12_trial_orgs, fn org ->
      send_day_12_email_to_org(org)
    end)

    Logger.info("Completed day 12 follow-up email task")
    :ok
  end

  @doc """
  Sends day 14 follow-up emails to trial users on their last day of trial
  """
  @spec send_day_14_followup_emails() :: :ok
  def send_day_14_followup_emails do
    Logger.info("Starting day 14 follow-up email task")

    # Calculate the date range for trials that are expiring today
    # Since trial is 14 days, day 14 means trial expires today (0-1 days remaining)
    # We check for trials expiring in 0-1 days to catch the day 14 window
    now = DateTime.utc_now()
    one_day = DateTime.add(now, 1, :day)

    day_14_trial_orgs =
      Organization
      |> where([o], o.is_trial_org == true)
      |> where([o], not is_nil(o.trial_expiration_date))
      |> where([o], o.trial_expiration_date >= ^now)
      |> where([o], o.trial_expiration_date < ^one_day)
      |> Repo.all(skip_organization_id: true)

    Enum.each(day_14_trial_orgs, fn org ->
      send_day_14_email_to_org(org)
    end)

    Logger.info("Completed day 14 follow-up email task")
    :ok
  end

  @spec send_day_3_email_to_org(Organization.t()) :: :ok | {:error, any()}
  defp send_day_3_email_to_org(%{id: organization_id} = organization) do
    Repo.put_process_state(organization_id)
    time = Glific.go_back_time(24)

    # Check if we've already sent the day 3 email
    if MailLog.mail_sent_in_past_time?("trial_day_3_followup", time, organization_id, []) do
      Logger.info("Day 3 follow-up email already sent for organization: #{organization_id}")
    else
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
    end

    :ok
  end

  @spec send_day_6_email_to_org(Organization.t()) :: :ok | {:error, any()}
  defp send_day_6_email_to_org(%{id: organization_id} = organization) do
    Repo.put_process_state(organization_id)
    time = Glific.go_back_time(24)

    # Check if we've already sent the day 6 email
    if MailLog.mail_sent_in_past_time?("trial_day_6_followup", time, organization_id, []) do
      Logger.info("Day 6 follow-up email already sent for organization: #{organization_id}")
    else
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
    end

    :ok
  end

  @spec send_day_12_email_to_org(Organization.t()) :: :ok | {:error, any()}
  defp send_day_12_email_to_org(%{id: organization_id} = organization) do
    Repo.put_process_state(organization_id)
    time = Glific.go_back_time(24)

    # Check if we've already sent the day 12 email
    if MailLog.mail_sent_in_past_time?("trial_day_12_followup", time, organization_id, []) do
      Logger.info("Day 12 follow-up email already sent for organization: #{organization_id}")
    else
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
    end

    :ok
  end

  @spec send_day_14_email_to_org(Organization.t()) :: :ok | {:error, any()}
  defp send_day_14_email_to_org(%{id: organization_id} = organization) do
    Repo.put_process_state(organization_id)
    time = Glific.go_back_time(24)

    # Check if we've already sent the day 14 email
    if MailLog.mail_sent_in_past_time?("trial_day_14_followup", time, organization_id, []) do
      Logger.info("Day 14 follow-up email already sent for organization: #{organization_id}")
    else
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
end
