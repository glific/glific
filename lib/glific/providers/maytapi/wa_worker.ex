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
    WAManagedPhones
  }

  require Logger

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, String.t()} | {:snooze, pos_integer()}
  def perform(%Oban.Job{args: %{"message" => message}} = job) do
    organization = Partners.organization(message["organization_id"])

    if is_nil(organization.services["bsp"]) do
      Worker.handle_credential_error(message)
    else
      perform(job, organization)
    end
  end

  def perform(%Oban.Job{args: %{"organization_id" => org_id}}) do
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
           organization.services["bsp"].keys["bsp_limit"]
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
    case update_credentials(org_id) do
      :ok ->
        send_notification(org_id, "Credentials updated successfully", Notifications.types().info)

      {:error, reason} ->
        Logger.error("Credential update failed: #{inspect(reason)}")

        send_notification(
          org_id,
          "Credential update failed: #{inspect(reason)}",
          Notifications.types().critical
        )
    end
  end

  @spec update_credentials(non_neg_integer()) :: :ok | {:error, String.t()}
  defp update_credentials(org_id) do
    with :ok <- WAManagedPhones.fetch_wa_managed_phones(org_id),
         :ok <- WAGroups.fetch_wa_groups(org_id),
         :ok <- WAGroups.set_webhook_endpoint(Partners.organization(org_id)) do
      :ok
    else
      error -> error
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
