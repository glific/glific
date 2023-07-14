defmodule Glific.Jobs.MinuteWorker do
  @moduledoc """
  Processes the tasks that need to be handled on a minute schedule
  """

  use Oban.Worker,
    queue: :crontab,
    max_attempts: 3

  require Logger

  alias Glific.{
    BigQuery.BigQueryWorker,
    Contacts,
    Erase,
    Flags,
    Flows.BroadcastWorker,
    Flows.FlowContext,
    GCS.GcsWorker,
    Jobs.BSPBalanceWorker,
    Partners,
    Partners.Billing,
    Searches.CollectionCount,
    Stats,
    Templates,
    Trackers,
    Triggers
  }

  @doc """
  Worker to implement cron job functionality as implemented by Oban. This
  is a work in progress and subject to change
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) ::
          :discard | :ok | {:error, any} | {:ok, any} | {:snooze, pos_integer()}
  def perform(%Oban.Job{args: %{"job" => job}} = args) do
    Logger.info("Performing job: #{inspect(job)}")
    services = Partners.get_organization_services()
    perform(args, services)
  end

  @spec perform(Oban.Job.t(), map()) ::
          :discard | :ok | {:error, any} | {:ok, any} | {:snooze, pos_integer()}
  defp perform(%Oban.Job{args: %{"job" => job}} = args, services)
       when job in [
              "contact_status",
              "wakeup_flows",
              "bigquery",
              "gcs",
              "triggers_and_broadcast",
              "stats"
            ] do
    # This is a bit simpler and shorter than multiple function calls with pattern matching
    case job do
      "contact_status" ->
        Partners.perform_all(&Contacts.update_contact_status/2, args, [])

      "wakeup_flows" ->
        Partners.perform_all(&FlowContext.wakeup_flows/1, nil, [])

      "triggers_and_broadcast" ->
        Partners.perform_all(&Triggers.execute_triggers/1, nil, [])
        Partners.perform_all(&BroadcastWorker.execute/1, nil, [])

      "bigquery" ->
        Partners.perform_all(&BigQueryWorker.perform_periodic/1, nil, services["bigquery"],
          only_recent: true
        )

      "gcs" ->
        Partners.perform_all(
          &GcsWorker.perform_periodic/1,
          nil,
          services["google_cloud_storage"],
          only_recent: true
        )

      "stats" ->
        Stats.generate_stats([], false)
    end

    :ok
  end

  defp perform(%Oban.Job{args: %{"job" => job}} = _args, services)
       when job in [
              "daily_tasks",
              "tracker_tasks",
              "hourly_tasks",
              "delete_tasks",
              "five_minute_tasks",
              "update_hsms",
              "weekly_tasks"
            ] do
    # This is a bit simpler and shorter than multiple function calls with pattern matching
    case job do
      "daily_tasks" ->
        Partners.perform_all(&Glific.Clients.daily_tasks/1, nil, [])
        Partners.perform_all(&Billing.update_usage/2, %{time: DateTime.utc_now()}, [])
        Erase.perform_daily()
        Partners.perform_all(&Erase.clean_messages/1, nil, [])
        Partners.perform_all(&Glific.Sheets.sync_organization_sheets/1, nil, [])

      "tracker_tasks" ->
        Trackers.daily_tasks()

      "weekly_tasks" ->
        Partners.perform_all(&Glific.Clients.weekly_tasks/1, nil, [])
        Erase.perform_weekly()

      "delete_tasks" ->
        # lets do this first, before we delete any records, so we have a better picture
        # of the DB we generate for all organizations, not the most recent ones
        FlowContext.delete_completed_flow_contexts()
        FlowContext.delete_old_flow_contexts()

      "hourly_tasks" ->
        Partners.unsuspend_organizations()

        Partners.perform_all(&BSPBalanceWorker.perform_periodic/1, nil, [], only_recent: true)

        Partners.perform_all(&BigQueryWorker.periodic_updates/1, nil, services["bigquery"],
          only_recent: true
        )

        Partners.perform_all(&Glific.Clients.hourly_tasks/1, nil, [])

      "five_minute_tasks" ->
        Partners.perform_all(&Flags.out_of_office_update/1, nil, services["fun_with_flags"])
        CollectionCount.collection_stats()

      "update_hsms" ->
        Partners.perform_all(&Templates.sync_hsms_from_bsp/1, nil, [])

      _ ->
        raise ArgumentError, message: "This job is not handled"
    end

    :ok
  end
end
