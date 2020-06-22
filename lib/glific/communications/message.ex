defmodule Glific.Communications.Message do
  @moduledoc """
  The Message Communication Context, which encapsulates and manages tags and the related join tables.
  """

  alias Glific.{
    Communications,
    Contacts,
    Contacts.Contact,
    Messages,
    Messages.Message,
    Processor.Producer,
    Repo
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

    if(Contacts.can_send_message_to?(message.receiver)) do
      apply(provider_module(), @type_to_token[message.type], [message])
      {:ok, Communications.publish_data(message, :sent_message)}
    else
       {:error, "Can not send the message to the contact."}
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
      flow: :outbound,
      sent_at: DateTime.truncate(DateTime.utc_now(), :second)
    })

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
    |> Messages.update_message(%{provider_status: :error, flow: :outbound})

    {:error, response.body}
  end

  @doc """
  Callback to update the provider status for a message
  """
  @spec update_provider_status(String.t(), atom()) :: {:ok, Message.t()}
  def update_provider_status(provider_message_id, provider_status) do
    # Improve me
    # We will improve that and complete this action in a Single Query.

    case Repo.fetch_by(Message, %{provider_message_id: provider_message_id}) do
      {:ok, message} ->
        Messages.update_message(message, %{provider_status: provider_status})
        {:ok, message}

      _ ->
        {:ok, nil}
    end
  end

  @doc """
  Callback when we receive a text message
  """

  @spec receive_text(map()) :: :ok
  def receive_text(message_params) do
    {:ok, contact} =
      Contacts.upsert(message_params.sender)
      |> Contacts.update_contact(%{last_message_at: DateTime.utc_now()})

    message_params
    |> Map.merge(%{
      type: :text,
      sender_id: contact.id,
      receiver_id: organization_contact_id(),
      flow: :inbound
    })
    |> Messages.create_message()
    |> Communications.publish_data(:received_message)
    |> Producer.add()
  end

  @doc """
  Callback when we receive a media (image|video|audio) message
  """
  @spec receive_media(map()) :: :ok
  def receive_media(message_params) do
    {:ok, contact} =
      Contacts.upsert(message_params.sender)
      |> Contacts.update_contact(%{last_message_at: DateTime.utc_now()})

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

    :ok
  end

  @doc false
  @spec provider_module() :: atom()
  def provider_module do
    provider = Communications.effective_provider()
    String.to_existing_atom(to_string(provider) <> ".Message")
  end

  @doc false
  @spec organization_contact_id() :: integer()
  def organization_contact_id do
    {:ok, contact} = Repo.fetch_by(Contact, %{phone: "917834811114"})
    contact.id
  end
end
