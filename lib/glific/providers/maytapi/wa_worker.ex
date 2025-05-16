defmodule Glific.Providers.Maytapi.WAWorker do
  @moduledoc """
  A worker to handle send message in whatsapp group processes
  """
  import Ecto.Query, warn: false

  use Oban.Worker,
    queue: :wa_group,
    max_attempts: 2,
    priority: 0

  alias Glific.{
    Groups.WAGroups,
    Messages.Message,
    Notifications,
    Notifications.Notification,
    Partners,
    Partners.Organization,
    Providers.Maytapi.ApiClient,
    Providers.Maytapi.ResponseHandler,
    Providers.Worker,
    Repo,
    WAManagedPhones
  }

  require Logger
  @default_bsp_limit 30
  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, String.t()} | {:snooze, pos_integer()}
  def perform(%Oban.Job{args: %{"message" => message}} = job) do
    organization = Partners.organization(message["organization_id"])

    # organization.services["bsp"] was relying on Gupshup being active or not
    if is_nil(organization.services["maytapi"]) do
      Worker.handle_credential_error(message)
    else
      perform(job, organization)
    end
  end

  def perform(%Oban.Job{args: %{"organization_id" => org_id, "update_credential" => true}}) do
    perform_credential_update(org_id)
  end

  @spec perform(Oban.Job.t(), Organization.t()) ::
          :ok | {:error, String.t()} | {:snooze, pos_integer()}
  defp perform(
         %Oban.Job{args: %{"message" => message, "payload" => payload}},
         organization
       ) do
    # ensure that we are under the rate limit, all rate limits are in requests/minutes
    # Refactoring because of credo warning
    case ExRated.check_rate(
           organization.shortcode,
           # the bsp limit is per organization per shortcode
           1000,
           @default_bsp_limit
         ) do
      {:ok, _} ->
        process_maytapi(organization.id, payload, message)

      _ ->
        Worker.default_send_rate_handler()
    end
  end

  @spec process_maytapi(non_neg_integer(), map(), map()) ::
          {:ok, Message.t()} | {:error, String.t()}
  defp process_maytapi(org_id, payload, message) do
    phone_id = payload["phone_id"]

    ApiClient.send_message(org_id, payload, phone_id)
    |> ResponseHandler.handle_response(message)
  end

  @spec perform_credential_update(non_neg_integer()) ::
          {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}
  defp perform_credential_update(org_id) do
    Repo.put_process_state(org_id)

    case update_credentials(org_id) do
      :ok ->
        send_notification(
          org_id,
          "Syncing of WhatsApp groups and contacts has been completed successfully.",
          Notifications.types().info
        )

      {:error, reason} ->
        Logger.error("WhatsApp group data sync failed: #{inspect(reason)}")

        send_notification(
          org_id,
          "WhatsApp group data sync failed: #{inspect(reason)}",
          Notifications.types().critical
        )
    end
  end

  @spec update_credentials(non_neg_integer()) :: :ok | {:error, String.t()}
  defp update_credentials(org_id) do
    with :ok <- WAManagedPhones.delete_existing_wa_managed_phones(org_id),
         :ok <- WAManagedPhones.fetch_wa_managed_phones(org_id),
         :ok <- WAGroups.fetch_wa_groups(org_id) do
      WAGroups.set_webhook_endpoint(Partners.organization(org_id))
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec send_notification(non_neg_integer(), String.t(), String.t()) ::
          {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}
  defp send_notification(org_id, message, severity) do
    Notifications.create_notification(%{
      category: "WhatsApp Groups",
      message: message,
      severity: severity,
      organization_id: org_id,
      entity: %{
        Provider: "Maytapi"
      }
    })
  end

  @doc """
  Periodically fetches WhatsApp groups and syncs them in Glific.
  """
  @spec perform_periodic(non_neg_integer()) :: :ok
  def perform_periodic(org_id) do
    WAGroups.fetch_wa_groups(org_id)

    Logger.info("Completed WhatsApp groups sync for organization: #{org_id}")
    :ok
  end
end
