defmodule Glific.WhatsappForms.WhatsappFormWorker do
  @moduledoc """
  Oban worker to sync WhatsApp forms for an organization.
  """
  require Logger

  alias Glific.{
    Notifications,
    Notifications.Notification,
    Providers.Gupshup.WhatsappForms.ApiClient,
    Repo,
    WhatsappForms
  }

  use Oban.Worker,
    queue: :default,
    max_attempts: 2,
    priority: 2

  @doc """
  Schedules the next WhatsApp form sync job for an organization.
  Takes a list of remaining forms and schedules the next job with rate limiting.
  """
  @spec schedule_next_form_sync(list(map()), non_neg_integer()) :: {:ok, any()} | {:error, any()}
  def schedule_next_form_sync(forms, org_id) do
    case forms do
      [first | rest] ->
        __MODULE__.new(
          %{
            "organization_id" => org_id,
            "form" => first,
            "forms" => rest,
            "sync_single" => true
          },
          schedule_in: 1
        )
        |> Oban.insert()

      [] ->
        Logger.info("[WORKER] All forms processed for org #{org_id}")

        send_notification(
          org_id,
          "Whatsapp form sync completed successfully.",
          Notifications.types().info
        )
    end
  end

  @impl Oban.Worker
  @doc """
  Standard perform method to use Oban worker
  """
  @spec perform(Oban.Job.t()) :: {:error, any()} | :ok
  def perform(%Oban.Job{
        args: %{
          "organization_id" => org_id,
          "form" => current_form,
          "forms" => remaining_forms,
          "sync_single" => true
        }
      }) do
    Repo.put_process_state(org_id)

    with {:ok, form_json} <- ApiClient.get_whatsapp_form_assets(current_form["id"], org_id),
         {:ok, _} <- WhatsappForms.sync_single_form(current_form, form_json, org_id) do
      Logger.info("[WORKER] Form #{current_form["id"]} synced successfully")
    else
      {:error, reason} ->
        Logger.error("Failed to process form #{current_form["id"]}: #{inspect(reason)}")
    end

    schedule_next_form_sync(remaining_forms, org_id)
    :ok
  end

  @spec send_notification(non_neg_integer(), String.t(), String.t()) ::
          {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}
  defp send_notification(org_id, message, severity) do
    Notifications.create_notification(%{
      category: "WhatsApp Forms",
      message: message,
      severity: severity,
      organization_id: org_id,
      entity: %{Provider: "Gupshup"}
    })
  end
end
