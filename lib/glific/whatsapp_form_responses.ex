defmodule Glific.WhatsappFormResponses do
  @moduledoc """
  Module to handle WhatsApp Form Responses
  """

  alias Glific.{Contacts, Partners, Messages, WhatsappForms.WhatsappFormResponse, Repo}

  @doc """
  Create a WhatsApp form response from the given attributes
  """
  @spec create_whatsapp_form_response(map()) :: {:ok, WhatsappFormResponse.t()} | {:error, any()}
  def create_whatsapp_form_response(attrs) do
    phone_number = attrs["from"]
    nfm_reply = attrs["interactive"]["nfm_reply"]
    response_json = nfm_reply["response_json"]
    timestamp = attrs["timestamp"]

    with {:ok, contact} <- get_contact_by_phone(phone_number),
         {:ok, raw_response} <- Jason.decode(response_json),
         {:ok, submitted_at} <- parse_timestamp(timestamp),
         {:ok, form_response} <- create_form_response(contact, raw_response, submitted_at) do
      {:ok, form_response}
    else
      error -> error
    end
  end

  @spec get_contact_by_phone(String.t()) :: {:ok, Contacts.Contact.t()} | {:error, atom()}
  defp get_contact_by_phone(phone_number) do
    case Contacts.get_contact_by_phone!(phone_number) do
      nil -> {:error, :contact_not_found}
      contact -> {:ok, contact}
    end
  rescue
    _ -> {:error, :contact_not_found}
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

  @spec create_form_response(Contacts.Contact.t(), map(), DateTime.t()) ::
          {:ok, WhatsappFormResponse.t()} | {:error, any()}
  defp create_form_response(contact, raw_response, submitted_at) do
    organization = Partners.organization(Repo.get_organization_id())

    response_attrs = %{
      raw_response: raw_response,
      submitted_at: submitted_at,
      contact_id: contact.id,
      whatsapp_form_id: "1",
      organization_id: organization.id
    }

    %WhatsappFormResponse{}
    |> WhatsappFormResponse.changeset(response_attrs)
    |> Repo.insert()
  end
end
