defmodule Glific.Communications.GroupMessage do
  @moduledoc """
  The Message Communication Context, which encapsulates and manages tags and the related join tables.
  """

  require Logger

  alias Glific.{
    Communications,
    Contacts,
    Contacts.Contact,
    Groups.WAGroups,
    Messages,
    Repo,
    WAGroup.WAManagedPhone,
    WAGroup.WAMessage,
    WAMessages
  }

  @doc false
  defmacro __using__(_opts \\ []) do
    quote do
    end
  end

  @type_to_token %{
    text: :send_text,
    image: :send_image,
    audio: :send_audio,
    video: :send_video,
    document: :send_document,
    sticker: :send_sticker,
    location_request_message: :send_interactive
  }

  @doc """
  Send message to receiver using define provider.
  """
  @spec send_message(WAMessage.t(), map()) :: {:ok, WAMessage.t()} | {:error, String.t()}
  def send_message(message, attrs) do
    message = Repo.preload(message, :media)

    Logger.info(
      "Sending message: type: '#{message.type}', contact_id: '#{message.contact_id}', message_id: '#{message.id}'"
    )

    with {:ok, _} <-
           apply(
             Glific.Providers.Maytapi.WAMessages,
             @type_to_token[message.type],
             [message, attrs]
           ) do
      :telemetry.execute(
        [:glific, :wa_message, :sent],
        # currently we are not measuring latency
        %{duration: 1},
        %{
          type: message.type,
          contact_id: message.contact_id,
          organization_id: message.organization_id
        }
      )

      Communications.publish_data(
        message,
        :sent_wa_group_message,
        message.organization_id
      )

      {:ok, message}
    end
  rescue
    _ ->
      log_error(message, "Could not send message to contact: Check maytapi Setting")
  end

  @doc """
  Callback when we receive a message from whatsapp group providers
  """
  @spec receive_message(map(), atom()) :: :ok | {:error, String.t()}
  def receive_message(%{organization_id: organization_id} = message_params, type \\ :text) do
    Logger.info(
      "Received message: type: '#{type}', phone: '#{message_params.sender.phone}', id: '#{message_params[:bsp_id]}'"
    )

    {:ok, contact} =
      message_params.sender
      |> Map.put(:organization_id, organization_id)
      |> Contacts.maybe_create_contact()

    do_receive_message(contact, message_params, type)
  end

  @spec log_error(WAMessage.t(), String.t()) :: {:error, String.t()}
  defp log_error(message, reason) do
    {:ok, _} = WAMessages.update_message(message, %{status: :error})
    {:error, reason}
  end

  @spec do_receive_message(Contact.t(), map(), atom()) :: :ok | {:error, String.t()}
  defp do_receive_message(contact, message_params, type) do
    {:ok, contact} = Contacts.set_session_status(contact, :session)

    metadata = create_message_metadata(contact, message_params, type)

    message_params =
      message_params
      |> Map.merge(metadata)
      |> Map.merge(%{
        flow: :inbound,
        bsp_status: :delivered,
        status: :received
      })

    # publish a telemetry event about the message being received
    :telemetry.execute(
      [:glific, :wa_message, :received],
      # currently we are not measuring latency
      %{duration: 1},
      metadata
    )

    case type do
      :text -> receive_text(message_params)
      _ -> receive_media(message_params)
    end
  end

  # handler for receiving the text message
  @spec receive_text(map()) :: :ok
  defp receive_text(message_params) do
    message_params
    |> WAMessages.create_message()
    |> Communications.publish_data(
      :received_wa_group_message,
      message_params.organization_id
    )

    :ok
  end

  # handler for receiving the media (image|video|audio|document|sticker)  message
  @spec receive_media(map()) :: :ok
  defp receive_media(message_params) do
    {:ok, message_media} =
      message_params
      |> Map.put_new(:flow, :inbound)
      |> Messages.create_message_media()

    message_params
    |> Map.put(:media_id, message_media.id)
    |> WAMessages.create_message()
    |> Communications.publish_data(
      :received_wa_group_message,
      message_params.organization_id
    )

    :ok
  end

  @spec create_message_metadata(Contact.t(), map(), atom()) :: map()
  defp create_message_metadata(contact, message_params, type) do
    %WAManagedPhone{id: wa_managed_phone_id} =
      Repo.get_by(WAManagedPhone, %{
        organization_id: message_params.organization_id,
        phone: message_params.receiver
      })

    {:ok, group} =
      WAGroups.maybe_create_group(%{
        organization_id: message_params.organization_id,
        wa_managed_phone_id: wa_managed_phone_id,
        bsp_id: message_params.group_id,
        label: message_params.group_name
      })

    %{
      type: type,
      contact_id: contact.id,
      organization_id: contact.organization_id,
      wa_group_id: group.id,
      wa_managed_phone_id: wa_managed_phone_id
    }
  end
end
