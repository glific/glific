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
    Repo,
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
  Standard perform method to use Oban worker.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "payload" => payload,
      "whatsapp_form_id" => whatsapp_form_id,
      "organization_id" => organization_id
    } = args

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
end
