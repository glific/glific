defmodule Glific.Providers.Gupshup.Message do
  @moduledoc """
  Messgae API layer between application and Gupshup
  """

  @channel "whatsapp"
  @behaviour Glific.Providers.MessageBehaviour
  @template_url "http://api.gupshup.io/sm/api/v1/template/msg"
  alias Glific.{
    Contacts,
    Communications,
    Messages.Message,
    Partners,
    Templates.SessionTemplate
  }

  @doc false
  @impl Glific.Providers.MessageBehaviour
  @spec send_text(Message.t()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_text(message) do
    %{type: :text, text: message.body, isHSM: message.is_hsm}
    |> send_message(message)
  end

  def send_hsm(hsm_template, params, attrs) do
    organization = Partners.organization(attrs.organization_id)
    app_name = organization.services["bsp"].secrets["app_name"]
    source = Contacts.get_contact!(attrs.sender_id)

    body = %{
      "source" => source.phone,
      "destination" => attrs.receiver.phone,
      "template" => %{"id" => hsm_template.uuid, "params" => params},
      "src.name" => app_name
    }

    hsm_template  = SessionTemplate.to_minimal_map(hsm_template)
    worker_module = Communications.provider_worker(attrs.organization_id)
    worker_args = %{hsm_template: hsm_template, payload: Jason.encode!(body)}

    apply(worker_module, :new, [worker_args, [schedule_in: 5]])
    |> Oban.insert()
  end

  @doc false
  @impl Glific.Providers.MessageBehaviour
  @spec send_image(Message.t()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_image(message) do
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
  @spec send_audio(Message.t()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_audio(message) do
    message_media = message.media

    %{
      type: :audio,
      url: message_media.source_url
    }
    |> send_message(message)
  end

  @doc false
  @impl Glific.Providers.MessageBehaviour
  @spec send_video(Message.t()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_video(message) do
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
  @spec send_document(Message.t()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_document(message) do
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
  @spec send_sticker(Message.t()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_sticker(message) do
    message_media = message.media

    %{
      type: :sticker,
      url: message_media.url
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
      bsp_message_id: payload["id"],
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
      bsp_message_id: payload["id"],
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
      bsp_message_id: payload["id"],
      longitude: message_payload["longitude"],
      latitude: message_payload["latitude"],
      sender: %{
        phone: payload["sender"]["phone"],
        name: payload["sender"]["name"]
      }
    }
  end

  @doc false
  @spec format_sender(Message.t()) :: map()
  defp format_sender(message) do
    organization = Partners.organization(message.organization_id)

    %{
      "source" => message.sender.phone,
      "src.name" => organization.services["bsp"].secrets["app_name"]
    }
  end

  @doc false
  @spec send_message(map(), Message.t()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  defp send_message(payload, message) do
    request_body =
      %{"channel" => @channel}
      |> Map.merge(format_sender(message))
      |> Map.put(:destination, message.receiver.phone)
      |> Map.put("message", Jason.encode!(payload))

    worker_module = Communications.provider_worker(message.organization_id)
    worker_args = %{message: Message.to_minimal_map(message), payload: request_body}

    apply(worker_module, :new, [worker_args, [scheduled_at: message.send_at]])
    |> Oban.insert()
  end
end
