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
    Groups.WAGroup,
    Groups.WAGroups,
    Messages.Message,
    Notifications,
    Notifications.Notification,
    Partners,
    Partners.Organization,
    Providers.Maytapi.ApiClient,
    Providers.Maytapi.Instrumentation,
    Providers.Maytapi.ResponseHandler,
    Providers.Maytapi.Sender,
    Providers.Worker,
    Repo,
    WAGroup.WAManagedPhone,
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
    Repo.put_process_state(org_id)
    phone_id = payload["phone_id"]
    response = ApiClient.send_message(org_id, payload, phone_id)

    cond do
      Map.get(payload, "retried", false) ->
        ResponseHandler.handle_response(response, message)

      ResponseHandler.phone_level_error?(response) ->
        retry_with_failover(response, org_id, payload, message)

      true ->
        ResponseHandler.handle_response(response, message)
    end
  end

  # Phase 4 failover retry: a single send-time retry through the next
  # active phone in the group. Sender.pick_for_send/2 promotes the
  # fallback phone on success.
  @spec retry_with_failover(any(), non_neg_integer(), map(), map()) ::
          {:ok, any()} | {:error, any()} | :ok
  defp retry_with_failover(original_response, org_id, payload, message) do
    with {:ok, wa_group} <-
           Repo.fetch_by(WAGroup, %{id: message["wa_group_id"], organization_id: org_id}),
         {:ok, failed_phone} <-
           Repo.fetch_by(WAManagedPhone, %{
             phone_id: payload["phone_id"],
             organization_id: org_id
           }),
         {:ok, new_phone, :promoted} <-
           Sender.pick_for_send(wa_group,
             exclude: [failed_phone.id],
             reason: :send_error
           ) do
      Logger.info(
        "Maytapi send retry: wa_group=#{wa_group.id} via phone=#{new_phone.phone} (excluded=#{failed_phone.phone})"
      )

      Appsignal.increment_counter("glific.maytapi.retry_with_failover", 1, %{result: "started"})

      new_payload =
        payload
        |> Map.put("phone_id", new_phone.phone_id)
        |> Map.put("retried", true)

      org_id
      |> ApiClient.send_message(new_payload, new_phone.phone_id)
      |> ResponseHandler.handle_response(message)
    else
      result ->
        log_retry_skip(result, message, payload, org_id)
        ResponseHandler.handle_response(original_response, message)
    end
  end

  @spec log_retry_skip(any(), map(), map(), non_neg_integer()) :: :ok
  defp log_retry_skip({:error, reason}, _message, _payload, _org_id)
       when reason in [:no_active_phones, :promotion_failed],
       do: :ok

  defp log_retry_skip(result, message, payload, org_id) do
    Glific.log_error(
      "Maytapi send retry failed: wa_group=#{inspect(message["wa_group_id"])} phone_id=#{inspect(payload["phone_id"])} org=#{org_id} result=#{inspect(result)}"
    )

    Appsignal.increment_counter("glific.maytapi.send_failed", 1, %{source: "worker_retry"})
    :ok
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
        Logger.error("WhatsApp group data sync failed: #{Glific.SafeLog.safe_inspect(reason)}")

        send_notification(
          org_id,
          "WhatsApp group data sync failed: #{Glific.SafeLog.safe_inspect(reason)}",
          Notifications.types().critical
        )
    end
  end

  @spec update_credentials(non_neg_integer()) :: :ok | {:error, String.t()}
  defp update_credentials(org_id) do
    with :ok <- WAManagedPhones.delete_existing_wa_managed_phones(org_id),
         :ok <- WAManagedPhones.fetch_wa_managed_phones(org_id),
         :ok <- WAGroups.sync_wa_groups(org_id) do
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
    # This cron previously discarded the sync result and always logged
    # "Completed", so a failed sync was invisible. Track the outcome as a
    # provider action (mirrors Gupshup's `hsm_sync`) so the failure rate is
    # chartable/alertable. `sync_wa_groups/1` reports `{:error, _}` when it
    # can't reach Maytapi to list phones; per-phone group errors inside it are
    # still swallowed there, so this is a connectivity-level signal.
    case WAGroups.sync_wa_groups(org_id) do
      :ok ->
        Instrumentation.track_action("contact_sync", :success, org_id)
        Logger.info("Completed WhatsApp groups sync for organization: #{org_id}")

      {:error, reason} ->
        Instrumentation.track_action("contact_sync", :failure, org_id)
        Logger.warning("WhatsApp groups sync failed for organization #{org_id}: #{reason}")
    end

    :ok
  end
end
