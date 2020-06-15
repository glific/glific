defmodule Glific.Communications.Message do
  @moduledoc """
  The Message Communication Context, which encapsulates and manages tags and the related join tables.
  """

  alias Glific.{
    Communications,
    Contacts,
    Messages,
    Messages.Message
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
  @spec send_message(Message.t()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_message(message) do
    provider_module()
    |> apply(@type_to_token[message.type], [message])
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
      flow: :outbound
    })

    {:ok, message}
  end

  @doc """
  Callback in case of any error while sending the message
  """
  @spec handle_error_response(any(), Message.t()) :: {:error, String.t()}
  def handle_error_response(response, message) do
    message
    |> Poison.encode!()
    |> Poison.decode!(as: %Message{})
    |> Messages.update_message(%{provider_status: :error, flow: :outbound})

    {:error, response.body}
  end

  @doc """
  Callback when we receive a text message
  """

  @spec receive_text(map()) :: Message.t()
  def receive_text(message_params) do
    contact = Contacts.upsert(message_params.sender)

    message_params
    |> Map.merge(%{
      type: :text,
      sender_id: contact.id,
      receiver_id: organization_contact_id(),
      flow: :inbound
    })
    |> Messages.create_message()
    |> Communications.publish_data(:received_message)
    |> Glific.Processor.Producer.add
  end

  @doc """
  Callback when we receive a media (image|video|audio) message
  """
  @spec receive_media(map()) :: Message.t()
  def receive_media(message_params) do
    contact = Contacts.upsert(message_params.sender)
    {:ok, message_media} = Messages.create_message_media(message_params)

    message_params
    |> Map.merge(%{
      sender_id: contact.id,
      media_id: message_media.id,
      receiver_id: organization_contact_id(),
      flow: :inbound
    })
    |> Messages.create_message()
    |> Communications.publish_data(:received_message)
  end

  @doc false
  @spec provider_module() :: atom()
  def provider_module do
    provider = Glific.Communications.effective_provider()
    String.to_existing_atom(to_string(provider) <> ".Message")
  end

  @doc false
  @spec organization_contact_id() :: integer()
  def organization_contact_id do
    {:ok, contact} = Glific.Repo.fetch_by(Contacts.Contact, %{name: "Default receiver"})
    contact.id
  end
end
