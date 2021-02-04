defmodule Glific.Jobs.MinuteWorker do
  @moduledoc """
  Processes the tasks that need to be handled on a minute schedule
  """

  use Oban.Worker,
    queue: :crontab,
    max_attempts: 3

  alias Glific.{
    Caches,
    Contacts,
    Flags,
    Flows.FlowContext,
    Jobs.BigQueryWorker,
    Jobs.BSPBalanceWorker,
    Jobs.ChatbaseWorker,
    Jobs.CollectionCountWorker,
    Jobs.GcsWorker,
    Partners,
    Templates
  }

  @global_organization_id 0

  @spec get_organization_services :: map()
  defp get_organization_services do
    case Caches.fetch(
           @global_organization_id,
           "organization_services",
           &load_organization_services/1
         ) do
      {:error, error} ->
        raise(ArgumentError,
          message: "Failed to retrieve organization services: #{error}"
        )

      {_, services} ->
        services
    end
  end

  # this is a global cache, so we kinda ignore the cache key
  @spec load_organization_services(tuple()) :: {:commit, map()}
  defp load_organization_services(_cache_key) do
    services =
      Partners.active_organizations([])
      |> Enum.reduce(
        %{},
        fn {id, _name}, acc ->
          load_organization_service(id, acc)
        end
      )
      |> combine_services()

    {:commit, services}
  end

  @spec load_organization_service(non_neg_integer, map()) :: map()
  defp load_organization_service(organization_id, services) do
    organization = Partners.organization(organization_id)

    service = %{
      "fun_with_flags" =>
        FunWithFlags.enabled?(
          :enable_out_of_office,
          for: %{organization_id: organization_id}
        ),
      "chatbase" => organization.services["chatbase"] != nil,
      "bigquery" => organization.services["bigquery"] != nil,
      "google_cloud_storage" => organization.services["google_cloud_storage"] != nil
    }

    Map.put(services, organization_id, service)
  end

  @spec add_service(map(), String.t(), boolean(), non_neg_integer) :: map()
  defp add_service(acc, _name, false, _org_id), do: acc

  defp add_service(acc, name, true, org_id) do
    value = Map.get(acc, name, [])
    Map.put(acc, name, [org_id | value])
  end

  @spec combine_services(map()) :: map()
  defp combine_services(services) do
    combined =
      services
      |> Enum.reduce(
        %{},
        fn {org_id, service}, acc ->
          acc
          |> add_service("fun_with_flags", service["fun_with_flags"], org_id)
          |> add_service("chatbase", service["chatbase"], org_id)
          |> add_service("bigquery", service["bigquery"], org_id)
          |> add_service("google_cloud_storage", service["google_cloud_storage"], org_id)
        end
      )

    Map.merge(services, combined)
  end

  @doc """
  Worker to implement cron job functionality as implemented by Oban. This
  is a work in progress and subject to change
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) ::
          :discard | :ok | {:error, any} | {:ok, any} | {:snooze, pos_integer()}
  def perform(%Oban.Job{args: %{"job" => _job}} = args) do
    services = get_organization_services()

    perform(args, services)
  end

  @spec perform(Oban.Job.t(), map()) ::
          :discard | :ok | {:error, any} | {:ok, any} | {:snooze, pos_integer()}
  defp perform(%Oban.Job{args: %{"job" => job}} = args, services)
       when job in ["contact_status", "wakeup_flows", "chatbase", "bigquery", "gcs"] do
    # This is a bit simpler and shorter than multiple function calls with pattern matching
    case job do
      "contact_status" ->
        Partners.perform_all(&Contacts.update_contact_status/2, args, [])

      "wakeup_flows" ->
        Partners.perform_all(&FlowContext.wakeup_flows/1, nil, [])

      "chatbase" ->
        Partners.perform_all(&ChatbaseWorker.perform_periodic/1, nil, services["chatbase"], true)

      "bigquery" ->
        Partners.perform_all(&BigQueryWorker.perform_periodic/1, nil, services["bigquery"], true)

      "gcs" ->
        Partners.perform_all(
          &GcsWorker.perform_periodic/1,
          nil,
          services["google_cloud_storage"],
          true
        )
    end

    :ok
  end

  defp perform(%Oban.Job{args: %{"job" => job}} = _args, services)
       when job in [
              "hourly_tasks",
              "five_minute_tasks",
              "update_hsms"
            ] do
    # This is a bit simpler and shorter than multiple function calls with pattern matching
    case job do
      "hourly_tasks" ->
        FlowContext.delete_completed_flow_contexts()
        FlowContext.delete_old_flow_contexts()
        Partners.perform_all(&BSPBalanceWorker.perform_periodic/1, nil, [], true)
        Partners.perform_all(&BigQueryWorker.periodic_updates/1, nil, services["bigquery"])

      "five_minute_tasks" ->
        Partners.perform_all(&CollectionCountWorker.perform_periodic/1, nil, [], true)
        Partners.perform_all(&Flags.out_of_office_update/1, nil, services["fun_with_flags"])

      "update_hsms" ->
        Partners.perform_all(&Templates.update_hsms/1, nil, [])

      _ ->
        raise ArgumentError, message: "This job is not handled"
    end

    :ok
  end
end
