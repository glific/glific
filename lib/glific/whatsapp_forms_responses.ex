defmodule Glific.WhatsappFormsResponses do
  @moduledoc """
  Module to handle WhatsApp Form Responses
  """
  import Ecto.Query, warn: false
  use Publicist
  require Logger

  alias Glific.{
    Messages.Message,
    Repo,
    Sheets,
    Sheets.GoogleSheets,
    WhatsappForms.WhatsappForm,
    WhatsappForms.WhatsappFormResponse,
    WhatsappForms.WhatsappFormWorker
  }

  @doc """
  Create a WhatsApp form response from the given attributes
  """
  @spec create_whatsapp_form_response(map()) ::
          {:ok, WhatsappFormResponse.t()} | {:error, Ecto.Changeset.t() | String.t() | any()}
  def create_whatsapp_form_response(attrs) do
    with {:ok, whatsapp_form} <- get_whatsapp_form(attrs.context_id, attrs.organization_id),
         {:ok, parsed_timestamp} <- parse_timestamp(attrs.submitted_at),
         {:ok, decoded_response} <- Jason.decode(attrs.raw_response),
         {:ok, result} <-
           do_create_whatsapp_form_response(%{
             raw_response: decoded_response,
             contact_id: attrs.sender_id,
             submitted_at: parsed_timestamp,
             whatsapp_form_id: whatsapp_form.id,
             organization_id: attrs.organization_id
           }) do
      payload = %{
        raw_response: result.raw_response,
        submitted_at: result.submitted_at,
        whatsapp_form_id: result.whatsapp_form_id,
        organization_id: result.organization_id,
        whatsapp_form_name: whatsapp_form.name,
        contact_number: attrs.sender.phone
      }

      WhatsappFormWorker.enqueue_write_to_sheet(whatsapp_form, payload)

      {:ok, result}
    end
  end

  @spec get_whatsapp_form(String.t(), non_neg_integer()) ::
          {:ok, WhatsappForm.t()} | {:error, String.t()}
  defp get_whatsapp_form(context_id, org_id) do
    with {:ok, previous_message} <-
           Repo.fetch_by(Message, %{bsp_message_id: context_id, organization_id: org_id}),
         %{template: template} <- Repo.preload(previous_message, [:template]),
         [%{"flow_id" => flow_id}] <- template.buttons,
         wa_form when not is_nil(wa_form) <- Repo.get_by(WhatsappForm, %{meta_flow_id: flow_id}) do
      {:ok, wa_form}
    else
      _ -> {:error, "WhatsApp Form not found for the given template_id"}
    end
  end

  @spec parse_timestamp(String.t()) :: {:ok, DateTime.t()} | {:error, atom()}
  defp parse_timestamp(timestamp) do
    DateTime.from_unix(String.to_integer(timestamp))
  end

  @spec do_create_whatsapp_form_response(any()) ::
          {:ok, WhatsappFormResponse.t()} | {:error, any()}
  defp do_create_whatsapp_form_response(attrs) do
    %WhatsappFormResponse{}
    |> WhatsappFormResponse.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Write WhatsApp form response to Google Sheet.
  """
  @spec write_to_google_sheet(map(), WhatsappForm.t()) ::
          {:ok, map()} | {:error, any()}
  def write_to_google_sheet(response, %{sheet_id: sheet_id} = whatsapp_form)
      when not is_nil(sheet_id) do
    organization_id = response["organization_id"]

    Glific.Metrics.increment("Whatsapp Form Response Sheet Write", organization_id)

    with spreadsheet_id <- get_spreadsheet_id(whatsapp_form),
         {:ok, ordered_row} <- prepare_row_from_headers(response, spreadsheet_id),
         {:ok, values} <-
           insert_row_in_sheet(organization_id, spreadsheet_id, ordered_row) do
      {:ok, values}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def write_to_google_sheet(response, _whatsapp_form) do
    {:ok, response}
  end

  @spec get_spreadsheet_id(WhatsappForm.t()) :: String.t()
  defp get_spreadsheet_id(whatsapp_form) do
    whatsapp_form = Repo.preload(whatsapp_form, [:sheet])
    Sheets.extract_spreadsheet_id(whatsapp_form.sheet.url)
  end

  @spec insert_row_in_sheet(non_neg_integer(), String.t(), list(String.t())) ::
          {:ok, any()} | {:error, any()}
  defp insert_row_in_sheet(organization_id, spreadsheet_id, values) do
    GoogleSheets.insert_row(organization_id, spreadsheet_id, %{
      range: "A:A",
      data: [values]
    })

    {:ok, values}
  end

  @spec prepare_row_from_headers(map(), String.t()) ::
          {:ok, list(String.t())} | {:error, any()}
  defp prepare_row_from_headers(response, spreadsheet_id) do
    organization_id = response["organization_id"]
    raw_response = response["raw_response"]

    payload =
      raw_response
      |> Map.delete("flow_token")
      |> Map.put("contact_phone_number", response["contact_number"])
      |> Map.put("timestamp", response["submitted_at"])
      |> Map.put("whatsapp_form_id", response["whatsapp_form_id"])
      |> Map.put("whatsapp_form_name", response["whatsapp_form_name"])

    with {:ok, headers} <- GoogleSheets.get_headers(organization_id, spreadsheet_id) do
      ordered_row =
        Enum.map(headers, fn header ->
          Map.get(payload, header, "")
        end)

      {:ok, ordered_row}
    end
  end
end
