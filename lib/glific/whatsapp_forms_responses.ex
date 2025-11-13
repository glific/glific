defmodule Glific.WhatsappFormsResponses do
  @moduledoc """
  Module to handle WhatsApp Form Responses
  """

  alias Glific.{Repo, WhatsappForms.WhatsappFormResponse}

  @doc """
  Create a WhatsApp form response from the given attributes
  """
  @spec create_whatsapp_form_response(map()) :: {:ok, WhatsappFormResponse.t()} | {:error, any()}
  def create_whatsapp_form_response(attrs) do
    with {:ok, parsed_timestamp} <- parse_timestamp(attrs.submitted_at),
         {:ok, decoded_response} <- Jason.decode(attrs.raw_response) do
      %{
        raw_response: decoded_response,
        contact_id: attrs.sender_id,
        submitted_at: parsed_timestamp,
        whatsapp_form_id: "1",
        organization_id: attrs.organization_id
      }
      |> do_create_whatsapp_form_response()
    else
      error -> error
    end
  end

  @spec parse_timestamp(String.t()) :: {:ok, DateTime.t()} | {:error, atom()}
  defp parse_timestamp(timestamp) do
    case DateTime.from_unix(String.to_integer(timestamp)) do
      {:ok, dt} -> {:ok, dt}
      error -> error
    end
  rescue
    _ -> {:error, :invalid_timestamp}
  end

  @spec do_create_whatsapp_form_response(any()) ::
          {:ok, WhatsappFormResponse.t()} | {:error, any()}
  defp do_create_whatsapp_form_response(attrs) do
    %WhatsappFormResponse{}
    |> WhatsappFormResponse.changeset(attrs)
    |> Repo.insert()
  end
end
