defmodule Glific.Providers.Gupshup.Message do
  @moduledoc """
  Messgae API layer between application and Gupshup
  """

  @channel "whatsapp"
  @behaviour Glific.Providers.MessageBehaviour

  alias Glific.{
    Communications,
    Messages.Message
  }

  @doc false
  @impl Glific.Providers.MessageBehaviour
  @spec send_text(Message.t(), true) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_text(message, is_hsm) when is_hsm == true do
    %{type: :text, text: message.body, isHSM: true}
    |> send_message(message)
  end

  @doc false
  @impl Glific.Providers.MessageBehaviour
  @spec send_text(Message.t(), false) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_text(message, is_hsm) when is_hsm == false do
    %{type: :text, text: message.body}
    |> send_message(message)
  end

  @doc false

  @impl Glific.Providers.MessageBehaviour
  @spec send_image(Message.t(), false) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_image(message, is_hsm) when is_hsm == false do
    message_media = message.media

    %{
      type: :image,
      originalUrl: message_media.source_url,
      previewUrl: message_media.url,
      caption: message_media.caption
    }
    |> send_message(message)
  end

  @doc false

  @impl Glific.Providers.MessageBehaviour
  @spec send_audio(Message.t(), false) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_audio(message, is_hsm) when is_hsm == false do
    message_media = message.media

    %{
      type: :audio,
      url: message_media.source_url
    }
    |> send_message(message)
  end

  @doc false
  @impl Glific.Providers.MessageBehaviour
  @spec send_video(Message.t(), false) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_video(message, is_hsm) when is_hsm == false do
    message_media = message.media

    %{
      type: :video,
      url: message_media.source_url,
      caption: message_media.caption
    }
    |> send_message(message)
  end

  @doc false
  @impl Glific.Providers.MessageBehaviour
  @spec send_document(Message.t(), false) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_document(message, is_hsm) when is_hsm == false do
    message_media = message.media

    %{
      type: :file,
      url: message_media.source_url,
      filename: message_media.caption
    }
    |> send_message(message)
  end

  @doc false
  @impl Glific.Providers.MessageBehaviour
  @spec receive_text(payload :: map()) :: map()
  def receive_text(params) do
    payload = params["payload"]
    message_payload = payload["payload"]

    %{
      provider_message_id: payload["id"],
      body: message_payload["text"],
      sender: %{
        phone: payload["sender"]["phone"],
        name: payload["sender"]["name"]
      }
    }
  end

  @doc false
  @impl Glific.Providers.MessageBehaviour
  @spec receive_media(map()) :: map()
  def receive_media(params) do
    payload = params["payload"]
    message_payload = payload["payload"]

    %{
      provider_message_id: payload["id"],
      caption: message_payload["caption"],
      url: message_payload["url"],
      source_url: message_payload["url"],
      sender: %{
        phone: payload["sender"]["phone"],
        name: payload["sender"]["name"]
      }
    }
  end

  @doc false
  @impl Glific.Providers.MessageBehaviour
  @spec receive_location(map()) :: map()
  def receive_location(params) do
    payload = params["payload"]
    message_payload = payload["payload"]

    %{
      provider_message_id: payload["id"],
      longitude: message_payload["longitude"],
      latitude: message_payload["latitude"],
      sender: %{
        phone: payload["sender"]["phone"],
        name: payload["sender"]["name"]
      }
    }
  end

  @doc false
  @spec format_sender(map()) :: map()
  defp format_sender(sender) do
    %{"source" => sender.phone, "src.name" => sender.name}
  end

  @doc false
  @spec send_message(map(), Message.t()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  defp send_message(payload, message) do
    request_body =
      %{"channel" => @channel}
      |> Map.merge(format_sender(message.sender))
      |> Map.put(:destination, message.receiver.phone)
      |> Map.put("message", Jason.encode!(payload))

    worker_module = Communications.provider_worker()
    worker_args = %{message: Message.to_minimal_map(message), payload: request_body}

    apply(worker_module, :new, [worker_args])
    |> Oban.insert()
  end

  @doc """
  Create and send OTP
  This function is going to be used by sms_adapter of passwordless_auth library
  """
  @spec create(map()) :: {:ok, String.t()}
  def create(request) do
    %{to: phone, code: otp} = request

    Glific.Messages.create_and_send_verification_message(phone, otp)

    {:ok, otp}
  end
end
