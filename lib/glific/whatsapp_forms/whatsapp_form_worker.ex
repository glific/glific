defmodule Glific.WhatsappForms.WhatsappFormWorker do
  @moduledoc """
  Oban worker for whatsapp forms.
  """
  require Logger

  use Oban.Worker,
    queue: :default,
    max_attempts: 2,
    priority: 1

  alias Glific.{
    Notifications,
    Notifications.Notification,
    Providers.Gupshup.WhatsappForms.ApiClient,
    Repo,
    WhatsappForms,
    WhatsappForms.WhatsappForm,
    WhatsappFormsResponses
  }

  @doc """
  Enqueue a job to write WhatsApp form response to Google Sheet.
  """
  @spec enqueue_write_to_sheet(WhatsappForm.t(), map()) :: {:ok, Oban.Job.t()}
  def enqueue_write_to_sheet(whatsapp_form, payload) do
    __MODULE__.new(%{
      payload: payload,
      whatsapp_form_id: whatsapp_form.id,
      organization_id: whatsapp_form.organization_id
    })
    |> Oban.insert()
  end

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

  @doc """
  Standard perform method to use Oban worker.
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: {:error, any()} | :ok
  def perform(%Oban.Job{
        args: %{
          "payload" => payload,
          "whatsapp_form_id" => whatsapp_form_id,
          "organization_id" => organization_id
        }
      }) do
    Repo.put_process_state(organization_id)

    whatsapp_form = Repo.get(WhatsappForm, whatsapp_form_id)

    case WhatsappFormsResponses.write_to_google_sheet(payload, whatsapp_form) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to write WhatsApp form response to Google Sheet: #{inspect(reason)}")

        {:error, reason}
    end
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
