defmodule Glific.Communications.Message do
  @moduledoc """
  The Message Communication Context, which encapsulates and manages tags and the related join tables.
  """
  import Ecto.Query

  alias Glific.{
    Communications,
    Contacts,
    Messages,
    Messages.Message,
    Partners,
    Processor.Producer,
    Repo,
    Taggers,
    Tags
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
    document: :send_document
  }

  @doc """
  Send message to receiver using define provider.
  """
  @spec send_message(Message.t()) :: {:ok, Message.t()} | {:error, String.t()}
  def send_message(message) do
    message = Repo.preload(message, [:receiver, :sender, :media])

    if Contacts.can_send_message_to?(message.receiver, message.is_hsm) do
      {:ok, _} = apply(Communications.provider(), @type_to_token[message.type], [message])
      {:ok, Communications.publish_data(message, :sent_message)}
    else
      {:ok, _} =
        Messages.update_message(message, %{status: :contact_opt_out, provider_status: nil})

      {:error, "Cannot send the message to the contact."}
    end
  end

  @doc """
  Callback when message send succsully
  """
  @spec handle_success_response(Tesla.Env.t(), Message.t()) :: {:ok, Message.t()}
  def handle_success_response(response, message) do
    body = response.body |> Jason.decode!()

    message
    |> Poison.encode!()
    |> Poison.decode!(as: %Message{})
    |> Messages.update_message(%{
      provider_message_id: body["messageId"],
      provider_status: :enqueued,
      status: :sent,
      flow: :outbound,
      sent_at: DateTime.truncate(DateTime.utc_now(), :second)
    })

    Tags.remove_tag_from_all_message(message["contact_id"], ["not-replied", "unread"])

    Taggers.TaggerHelper.tag_outbound_message(message)

    {:ok, message}
  end

  @doc """
  Callback in case of any error while sending the message
  """
  @spec handle_error_response(Tesla.Env.t(), Message.t()) :: {:error, String.t()}
  def handle_error_response(response, message) do
    message
    |> Poison.encode!()
    |> Poison.decode!(as: %Message{})
    |> Messages.update_message(%{
      provider_status: :error,
      status: :sent,
      flow: :outbound
    })

    {:error, response.body}
  end

  @doc """
  Callback to update the provider status for a message
  """
  @spec update_provider_status(String.t(), atom()) :: {:ok, Message.t()}
  def update_provider_status(provider_message_id, provider_status) do
    from(m in Message, where: m.provider_message_id == ^provider_message_id)
    |> Repo.update_all(set: [provider_status: provider_status, updated_at: DateTime.utc_now()])
  end

  @doc """
  Callback when we receive a message from whats app
  """
  @spec receive_message(map(), atom()) :: {:ok} | {:error, String.t()}
  def receive_message(message_params, type \\ :text) do
    {:ok, contact} =
      message_params.sender
      |> Map.put(:last_message_at, DateTime.utc_now())
      |> Contacts.upsert()

    {:ok, _} = Contacts.set_session_status(contact, :session)

    message_params =
      message_params
      |> Map.merge(%{
        type: type,
        sender_id: contact.id,
        receiver_id: Partners.organization_contact_id(),
        flow: :inbound,
        provider_status: :delivered,
        status: :delivered
      })

    cond do
      type in [:video, :audio, :image, :document] -> receive_media(message_params)
      type == :text -> receive_text(message_params)
      # For location and address messages, will add that when there will be a use case
      type == :location -> receive_location(message_params)
      true -> {:error, "Message type not supported"}
    end
  end

  # handler for receiving the text message
  @spec receive_text(map()) :: {:ok}
  defp receive_text(message_params) do
    message_params
    |> Messages.create_message()
    |> Taggers.TaggerHelper.tag_inbound_message()
    |> Communications.publish_data(:received_message)
    |> Producer.add()

    {:ok}
  end

  # handler for receiving the media (image|video|audio|document)  message
  @spec receive_media(map()) :: {:ok}
  defp receive_media(message_params) do
    {:ok, message_media} = Messages.create_message_media(message_params)

    message_params
    |> Map.put(:media_id, message_media.id)
    |> Messages.create_message()
    |> Communications.publish_data(:received_message)
    |> Producer.add()

    {:ok}
  end

  # handler for receiving the location message
  @spec receive_location(map()) :: {:ok}
  defp receive_location(message_params) do
    {:ok, message} = Messages.create_message(message_params)

    message_params
    |> Map.put(:contact_id, message_params.sender_id)
    |> Map.put(:message_id, message.id)
    |> Contacts.create_location()

    message
    |> Communications.publish_data(:received_message)

    {:ok}
  end
end
