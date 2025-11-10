defmodule GlificWeb.Providers.Gupshup.Controllers.WhatsAppController do
  @moduledoc """
  Controller for handling WhatsApp Business Account webhooks from Gupshup
  """

  use GlificWeb, :controller

  alias Glific.{Contacts, Partners, Messages}
  alias Glific.Repo
  alias Glific.WhatsappForms.WhatsappFormResponse

  require Logger

  @doc """
  Handle WhatsApp webhook events
  """
  def webhook(conn, params) do
    Logger.info("Received WhatsApp webhook: #{inspect(params)}")

    # Process the webhook data here
    # You can extract messages, contacts, interactions etc.
    process_webhook(params)

    json(conn, %{status: "ok"})
  end

  defp process_webhook(%{"entry" => entries}) do
    Enum.each(entries, &process_entry/1)
  end

  defp process_entry(%{"changes" => changes}) do
    Enum.each(changes, &process_change/1)
  end

  defp process_change(%{"field" => "messages", "value" => value}) do
    # Handle message events
    handle_messages(value)
  end

  defp process_change(_), do: :ok

  defp handle_messages(%{"messages" => messages, "contacts" => contacts}) do
    # Process messages and contacts
    Enum.each(messages, fn message ->
      process_message(message, contacts)
    end)
  end

  defp handle_messages(_), do: :ok

  defp process_message(
         %{"type" => "interactive", "interactive" => %{"type" => "nfm_reply"}} = message,
         contacts
       ) do
    # Extract form response data
    phone_number = message["from"]
    nfm_reply = message["interactive"]["nfm_reply"]
    response_json = nfm_reply["response_json"]
    timestamp = message["timestamp"]

    # Find contact by phone number
    organization = Partners.organization(Repo.get_organization_id())
    contact = Contacts.get_contact_by_phone!(phone_number)

    if contact do
      # Create the payload for whatsapp_form_responses
      payload = %{
        contact_id: contact.id,
        raw_response: Jason.decode!(response_json),
        submitted_at: DateTime.from_unix!(String.to_integer(timestamp)),
        organization_id: organization.id,
        message_id: message["id"],
        whatsapp_form_id: "30"
      }

      case WhatsappFormResponse.changeset(%WhatsappFormResponse{}, payload) |> Repo.insert() do
        {:ok, form_response} ->
          Logger.info("WhatsApp form response saved: #{inspect(form_response)}")
          IO.inspect(form_response, label: "Form Response")
          IO.inspect(form_response.id, label: "Form Response ID")
          # Create a new message with wa_form type
          message_attrs = %{
            body: "",
            type: :wa_form,
            flow: :inbound,
            contact_id: contact.id,
            organization_id: organization.id,
            wa_form_id: form_response.id,
            bsp_message_id: message["id"],
            sender_id: contact.id,
            receiver_id: "1",
            media_id: nil
          }

          case Messages.create_message(message_attrs) do
            {:ok, created_message} ->
              Logger.info("Message created successfully: #{inspect(created_message)}")

            {:error, changeset} ->
              Logger.error("Failed to create message: #{inspect(changeset)}")
          end

        {:error, changeset} ->
          Logger.error("Failed to save WhatsApp form response: #{inspect(changeset)}")
      end
    else
      Logger.warn("Contact not found for phone number: #{phone_number}")
    end
  end

  defp process_message(message, _contacts) do
    Logger.info("Processing non-form message: #{inspect(message)}")
  end
end
