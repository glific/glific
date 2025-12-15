defmodule Glific.WhatsappFormsResponses do
  @moduledoc """
  Module to handle WhatsApp Form Responses
  """

  alias Glific.{
    Sheets.GoogleSheets,
    Repo,
    Templates.SessionTemplate,
    WhatsappForms,
    WhatsappForms.WhatsappForm,
    WhatsappForms.WhatsappFormResponse
  }

  @doc """
  Create a WhatsApp form response from the given attributes
  """
  @spec create_whatsapp_form_response(map()) :: {:ok, WhatsappFormResponse.t()} | {:error, any()}
  def create_whatsapp_form_response(attrs) do
    with {:ok, whatsapp_form} <- get_wa_form(attrs.template_id),
         {:ok, parsed_timestamp} <- parse_timestamp(attrs.submitted_at),
         {:ok, decoded_response} <- Jason.decode(attrs.raw_response) do
      %{
        raw_response: decoded_response,
        contact_id: attrs.sender_id,
        submitted_at: parsed_timestamp,
        whatsapp_form_id: whatsapp_form.id,
        organization_id: attrs.organization_id
      }
      |> do_create_whatsapp_form_response()
      |> write_to_google_sheet(whatsapp_form)
    end
  end

  @spec get_wa_form(String.t()) :: {:ok, non_neg_integer()} | nil
  defp get_wa_form(template_id) do
    with template when not is_nil(template) <-
           Repo.get_by(SessionTemplate, %{uuid: template_id}),
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

  defp write_to_google_sheet({:ok, response}, whatsapp_form) do
    organization_id = response.organization_id

    payload =
      response.raw_response
      |> Map.delete("flow_token")
      |> Map.put("contact_id", to_string(response.contact_id))
      |> Map.put("timestamp", response.submitted_at |> DateTime.to_string())
      |> Map.put("whatsapp_form_id", to_string(response.whatsapp_form_id))

    with {:ok, spreadsheet_id} <- get_spreadsheet_id(whatsapp_form),
         {:ok, headers} <- GoogleSheets.get_headers(organization_id, spreadsheet_id),
         {:ok, ordered_row} <- prepare_row_from_headers(payload, headers) do
      GoogleSheets.insert_row(organization_id, spreadsheet_id, %{
        range: "A:A",
        data: [ordered_row]
      })
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_spreadsheet_id(whatsapp_form) do
    whatsapp_form = Repo.preload(whatsapp_form, [:sheet])
    url = whatsapp_form.sheet.url

    WhatsappForms.extract_spreadsheet_id(url)
  end

  defp write_to_google_sheet(error, _whatsapp_form), do: error

  @spec prepare_row_from_headers(map(), list(String.t())) ::
          {:ok, list(String.t())} | {:error, String.t()}
  defp prepare_row_from_headers(payload, headers) do
    payload_keys = MapSet.new(Map.keys(payload))
    header_keys = MapSet.new(headers)

    # Check if all payload keys exist in headers
    missing_keys = MapSet.difference(payload_keys, header_keys)

    if MapSet.size(missing_keys) > 0 do
      {:error,
       "Response keys do not match Google Sheet headers. Missing headers: #{Enum.join(missing_keys, ", ")}"}
    else
      # Create ordered row based on headers
      ordered_row =
        Enum.map(headers, fn header ->
          Map.get(payload, header, "")
        end)

      {:ok, ordered_row}
    end
  end
end
