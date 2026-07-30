defmodule Glific.Communications.WebMessage do
  @moduledoc """
  The web channel's message communication context — mirrors
  `Glific.Communications.GroupMessage`'s split-context shape, but for browser contacts
  connected over `GlificWeb.WebChannelSocket` instead of a BSP-backed WhatsApp group.

  Outbound send always goes through the hardcoded `Glific.Providers.Web.Message` provider
  (there is no per-organization BSP config for the web channel). Inbound messages arrive
  from `GlificWeb.WebChannel.RoomChannel`, are persisted, published to the staff inbox, and
  handed to the flow engine via the same poolboy path used for WhatsApp inbound.
  """

  require Logger

  alias Glific.Communications.Message, as: MessageCommunications

  alias Glific.{
    Communications,
    Contacts,
    Contacts.Contact,
    Messages,
    Messages.Message,
    Partners,
    Repo
  }

  @type_to_token %{
    text: :send_text,
    image: :send_image,
    audio: :send_audio,
    video: :send_video,
    document: :send_document
  }

  @doc """
  Send a web channel message to its receiver (a browser contact), via
  `Glific.Providers.Web.Message`.
  """
  @spec send_message(Message.t(), map()) :: {:ok, Message.t()} | {:error, String.t()}
  def send_message(message, attrs) do
    message = Repo.preload(message, [:receiver, :sender, :media])

    Logger.info(
      "Sending web message: type: '#{message.type}', contact_id: '#{message.receiver_id}', message_id: '#{message.id}'"
    )

    with {:ok, _} <-
           apply(
             Glific.Providers.Web.Message,
             @type_to_token[message.type],
             [message, attrs]
           ) do
      Communications.publish_data(message, :sent_message, message.organization_id)
      {:ok, message}
    end
  rescue
    _ ->
      log_error(message, "Could not send message to web channel contact")
  end

  @spec log_error(Message.t(), String.t()) :: {:error, String.t()}
  defp log_error(message, reason) do
    {:ok, _} = Messages.update_message(message, %{status: :error})
    {:error, reason}
  end

  @doc """
  Callback when we receive a message from a browser contact over the web channel.

  Contacts are shared across channels — this creates/reuses the contact by phone the same
  way WhatsApp inbound does, it just never touches `Contacts.set_session_status/2` (that's a
  WhatsApp session-window concept that doesn't apply to the web channel).
  """
  @spec receive_message(map(), atom()) :: :ok
  def receive_message(%{organization_id: organization_id} = message_params, type \\ :text) do
    {:ok, contact} =
      message_params.sender
      |> Map.put(:organization_id, organization_id)
      |> Contacts.maybe_create_contact()

    do_receive_message(contact, message_params, type)
  end

  @spec do_receive_message(Contact.t(), map(), atom()) :: :ok
  defp do_receive_message(contact, message_params, type) do
    metadata = create_message_metadata(contact, message_params)

    message_params =
      message_params
      |> Map.merge(metadata)
      |> Map.merge(%{
        type: type,
        flow: :inbound,
        channel: "web",
        bsp_status: :delivered,
        status: :received
      })

    message_params
    |> Messages.create_message()
    |> publish_data(:received_message, message_params.organization_id)
    |> MessageCommunications.process_message()

    :ok
  end

  @spec publish_data({:ok, Message.t()} | {:error, any()}, atom(), non_neg_integer()) ::
          Message.t() | nil
  defp publish_data({:error, changeset}, _data_type, _organization_id) do
    Glific.log_error(
      "Could not create inbound web message: #{Glific.SafeLog.safe_inspect(changeset.errors)}"
    )

    nil
  end

  defp publish_data({:ok, message}, data_type, organization_id),
    do: Communications.publish_data(message, data_type, organization_id)

  @spec create_message_metadata(Contact.t(), map()) :: map()
  defp create_message_metadata(contact, message_params) do
    %{
      sender_id: contact.id,
      contact_id: contact.id,
      receiver_id: Partners.organization_contact_id(message_params.organization_id),
      organization_id: contact.organization_id
    }
  end
end
