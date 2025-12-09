defmodule Glific.WhatsappForms.WhatsappFormWorker do
  @moduledoc """
  Oban worker to sync WhatsApp forms for an organization.
  """
  require Logger

  alias Glific.{
    Notification,
    Notifications,
    Notifications.Notification,
    Repo,
    WhatsappForms
  }

  use Oban.Worker,
    queue: :default,
    max_attempts: 2,
    priority: 2

  @doc """
  Create a job to sync WhatsApp forms for the given organization ID.
  """
  @spec create_forms_sync_job(non_neg_integer()) :: {:ok, Oban.Job.t()} | {:error, any()}
  def create_forms_sync_job(org_id) do
    __MODULE__.new(
      %{"organization_id" => org_id, "sync_forms" => true},
      unique: [
        period: 60 * 5,
        keys: [:organization_id],
        states: [:available, :scheduled, :executing]
      ]
    )
    |> Oban.insert()
  end

  @impl Oban.Worker
  @doc """
  Standard perform method to use Oban worker
  """
  @spec perform(Oban.Job.t()) :: {:error, any()} | :ok
  def perform(%Oban.Job{args: %{"organization_id" => org_id, "sync_forms" => true}}) do
    Repo.put_process_state(org_id)

    case WhatsappForms.sync_whatsapp_form(org_id) do
      :ok ->
        Logger.info("Whatsapp Form sync completed successfully for org_id: #{org_id}")

        send_notification(
          org_id,
          "Whatsapp form sync completed successfully.",
          Notifications.types().info
        )

      {:error, reason} ->
        Logger.error(
          "Failed to sync whatsapp form for org_id: #{org_id}, reason: #{inspect(reason)}"
        )

        send_notification(
          org_id,
          "Failed to sync whatsapp forms: #{inspect(reason)}",
          Notifications.types().critical
        )
    end

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
