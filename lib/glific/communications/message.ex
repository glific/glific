defmodule Glific.Communications.Message do
  @moduledoc """
  The Message Communication Context, which encapsulates and manages tags and the related join tables.
  """

  alias Glific.Contacts
  alias Glific.Messages
  alias Glific.Messages.Message

  @doc false
  defmacro __using__(_opts \\ []) do
    quote do
    end
  end

  @doc """
  Send message to receiver using define provider.
  """
  @spec send_message(%Message{:type => :text}) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_message(%Message{type: :text} = message) do
    message
    |> send_text()
  end

  @doc false
  @spec send_message(Message.t()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_message(message) do
    message
    |> send_media()
  end

  @doc false
  @spec send_text(%Message{:type => :text}) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  defp send_text(message) do
    provider_module()
    |> apply(:send_text, [message])
  end

  @doc false
  @spec send_media(Message.t()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  defp send_media(message) do
    case message.type do
      :image ->
        provider_module()
        |> apply(:send_image, [message])

      :audio ->
        provider_module()
        |> apply(:send_audio, [message])

      :video ->
        provider_module()
        |> apply(:send_video, [message])

      _ ->
        provider_module()
        |> apply(:send_document, [message])
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
      provider_status: :enqueued
    })

    {:ok, message}
  end

  @doc """
  Callback in case of any error while sending the message
  """
  @spec handle_error_response(Tesla.Env.t(), any) :: {:error, String.t()}
  def handle_error_response(response, _message) do
    {:error, response.body}
  end

  @doc """
  Callback when we receive a text message
  """

  @spec receive_text(map()) :: {:ok, Message.t()}
  def receive_text(message_params) do
    contact = Contacts.upsert(message_params.sender)
    IO.inspect("hhi")
    IO.inspect(message_params)
    message_params
    |> Map.merge(%{
      type: :text,
      sender_id: contact.id,
      receiver_id: organization_contact_id()
    })
    |> Messages.create_message()
    |> publish_message()
  end

  @doc """
  Callback when we receive a media (image|video|audio) message
  """
  @spec receive_media(map()) :: {:ok, Message.t()}
  def receive_media(message_params) do
    contact = Contacts.upsert(message_params.sender)
    {:ok, message_media} = Messages.create_message_media(message_params)

    message_params
    |> Map.merge(%{
      sender_id: contact.id,
      media_id: message_media.id,
      receiver_id: organization_contact_id()
    })
    |> Messages.create_message()
    |> publish_message()
  end

  @doc false
  @spec publish_message({:ok, Message.t()}) :: {:ok, Message.t()}
  defp publish_message({:ok, message}) do
    Absinthe.Subscription.publish(
      GlificWeb.Endpoint,
      message,
      received_message: "*"
    )

    {:ok, message}
  end

  @doc false
  @spec publish_message(String.t()) :: String.t()
  defp publish_message(err), do: err

  @doc false
  @spec provider_module() :: atom()
  def provider_module do
    provider = Glific.Communications.effective_provider()
    String.to_existing_atom(to_string(provider) <> ".Message")
  end

  @doc false
  @spec organization_contact_id() :: integer()
  def organization_contact_id do
    1
  end
end
