defmodule Glific.WhatsappFormsResponses do
  @moduledoc """
  Module to handle WhatsApp Form Responses
  """

  alias Glific.{
    Messages.Message,
    Repo,
    WhatsappForms.WhatsappForm,
    WhatsappForms.WhatsappFormResponse
  }

  @doc """
  Create a WhatsApp form response from the given attributes
  """
  @spec create_whatsapp_form_response(map()) :: {:ok, WhatsappFormResponse.t()} | {:error, any()}
  def create_whatsapp_form_response(attrs) do
    with {:ok, whatsapp_form_id} <-
           get_wa_form_id(attrs.context_id, attrs.organization_id),
         {:ok, parsed_timestamp} <- parse_timestamp(attrs.submitted_at),
         {:ok, decoded_response} <- Jason.decode(attrs.raw_response) do
      %{
        raw_response: decoded_response,
        contact_id: attrs.sender_id,
        submitted_at: parsed_timestamp,
        whatsapp_form_id: whatsapp_form_id,
        organization_id: attrs.organization_id
      }
      |> do_create_whatsapp_form_response()
    end
  end

  @spec get_wa_form_id(String.t(), non_neg_integer()) :: {:ok, non_neg_integer()} | nil
  defp get_wa_form_id(context_id, org_id) do
    with {:ok, previous_message} <-
           Repo.fetch_by(Message, %{bsp_message_id: context_id, organization_id: org_id}),
         %{template: template} <- Repo.preload(previous_message, [:template]),
         [%{"flow_id" => flow_id}] <- template.buttons,
         wa_form when not is_nil(wa_form) <- Repo.get_by(WhatsappForm, %{meta_flow_id: flow_id}) do
      {:ok, wa_form.id}
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
end
