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
    queue: :whatsapp_form,
    max_attempts: 2,
    priority: 2

  @rate_limit_per_sec 5
  @delay_ms div(1000, @rate_limit_per_sec)

  @doc """
  Create a job to sync WhatsApp forms for the given organization ID.
  """
  @spec create_forms_sync_job(non_neg_integer()) :: {:ok, Oban.Job.t()} | {:error, any()}
  def create_forms_sync_job(org_id) do
    __MODULE__.new(%{"organization_id" => org_id, "sync_forms" => true})
    |> Oban.insert()
  end

  @doc """
  Create a job to sync WhatsApp form JSON for all forms of a given organization.
  """
  @spec create_single_form_sync_job(list(map()), non_neg_integer()) :: :ok
  def create_single_form_sync_job(forms, org_id) do
    case forms do
      [first | rest] ->
        __MODULE__.new(%{
          "organization_id" => org_id,
          "form" => first,
          "forms" => rest,
          "sync_single" => true
        })
        |> Oban.insert(schedule_in: {:milliseconds, @delay_ms})

      [] ->
        Logger.info("[WORKER] No WhatsApp forms found for org #{org_id}")
        :ok
    end

    :ok
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

    case remaining_forms do
      [next | rest] ->
        __MODULE__.new(%{
          "organization_id" => org_id,
          "form" => next,
          "forms" => rest,
          "sync_single" => true
        })
        |> Oban.insert(schedule_in: {:milliseconds, @delay_ms})

      [] ->
        Logger.info("[WORKER] All forms processed for org #{org_id}")

        send_notification(
          org_id,
          "Whatsapp form sync completed successfully.",
          Notifications.types().info
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
