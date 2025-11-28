defmodule Glific.Providers.Gupshup.Message do
  @moduledoc """
  Message API layer between application and Gupshup
  """

  @behaviour Glific.Providers.MessageBehaviour

  alias Glific.{
    Communications,
    Messages.Message,
    Partners,
    Repo
  }

  import Ecto.Query, warn: false
  require Logger

  @channel "whatsapp"

  @doc false
  @spec send_text(Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  def send_text(message, attrs \\ %{}) do
    %{type: :text, text: message.body, isHSM: message.is_hsm, previewUrl: true}
    |> check_size()
    |> send_message(message, attrs)
  end

  @doc false
  @spec send_image(Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  def send_image(message, attrs \\ %{}) do
    message_media = message.media

    %{
      type: :image,
      originalUrl: message_media.source_url,
      previewUrl: message_media.url,
      caption: caption(message_media.caption)
    }
    |> check_size()
    |> send_message(message, attrs)
  end

  @doc false

  @spec send_audio(Message.t(), map()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_audio(message, attrs \\ %{}) do
    message_media = message.media

    %{
      type: :audio,
      url: message_media.source_url
    }
    |> send_message(message, attrs)
  end

  @doc false
  @spec send_video(Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  def send_video(message, attrs \\ %{}) do
    message_media = message.media

    %{
      type: :video,
      url: message_media.source_url,
      caption: caption(message_media.caption)
    }
    |> check_size()
    |> send_message(message, attrs)
  end

  @doc false
  @spec send_document(Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_document(message, attrs \\ %{}) do
    message_media = message.media

    %{
      type: :file,
      url: message_media.source_url,
      filename: message_media.caption
    }
    |> send_message(message, attrs)
  end

  @doc false
  @spec send_sticker(Message.t(), map()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_sticker(message, attrs \\ %{}) do
    message_media = message.media

    %{
      type: :sticker,
      url: message_media.url
    }
    |> send_message(message, attrs)
  end

  @doc false
  @spec send_interactive(Message.t(), map()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_interactive(message, attrs \\ %{}) do
    message.interactive_content
    |> Map.merge(%{type: message.type})
    |> send_message(message, attrs)
  end

  @doc false
  @spec caption(nil | String.t()) :: String.t()
  defp caption(nil), do: ""
  defp caption(caption), do: caption

  @spec context_id(map()) :: String.t() | nil
  defp context_id(payload),
    do: get_in(payload, ["context", "gsId"]) || get_in(payload, ["context", "id"])

  @doc false
  @spec receive_text(payload :: map()) :: map()
  def receive_text(params) do
    payload = params["payload"]
    message_payload = payload["payload"]

    # lets ensure that we have a phone number
    # sometime the gupshup payload has a blank payload
    # or maybe a simulator or some test code
    if payload["sender"]["phone"] in [nil, ""] do
      error = "Phone number is blank, #{inspect(payload)}"
      Glific.log_error(error)
      raise(RuntimeError, message: error)
    end

    %{
      bsp_message_id: payload["id"],
      context_id: context_id(payload),
      body: message_payload["text"],
      sender: %{
        phone: payload["sender"]["phone"],
        name: payload["sender"]["name"]
      }
    }
  end

  @doc false
  @spec receive_media(map()) :: map()
  def receive_media(params) do
    payload = params["payload"]
    message_payload = payload["payload"]

    %{
      bsp_message_id: payload["id"],
      context_id: context_id(payload),
      caption: message_payload["caption"],
      url: message_payload["url"],
      content_type: message_payload["contentType"],
      source_url: message_payload["url"],
      sender: %{
        phone: payload["sender"]["phone"],
        name: payload["sender"]["name"]
      }
    }
  end

  @doc false
  @spec receive_location(map()) :: map()
  def receive_location(params) do
    payload = params["payload"]
    message_payload = payload["payload"]

    %{
      bsp_message_id: payload["id"],
      context_id: context_id(payload),
      longitude: message_payload["longitude"],
      latitude: message_payload["latitude"],
      sender: %{
        phone: payload["sender"]["phone"],
        name: payload["sender"]["name"]
      }
    }
  end

  @doc false
  @spec receive_billing_event(map()) :: {:ok, map()} | {:error, String.t()}
  def receive_billing_event(params) do
    references = get_in(params, ["payload", "references"])
    deductions = get_in(params, ["payload", "deductions"])
    bsp_message_id = references["gsId"] || references["id"]

    message_id =
      Repo.fetch_by(Message, %{
        bsp_message_id: bsp_message_id
      })
      |> case do
        {:ok, message} -> message.id
        {:error, _error} -> nil
      end

    message_conversation = %{
      deduction_type: deductions["category"],
      is_billable: deductions["billable"],
      conversation_id: references["conversationId"],
      payload: params,
      message_id: message_id
    }

    {:ok, message_conversation}
  end

  @doc false
  @spec receive_interactive(map()) :: map()
  def receive_interactive(params) do
    payload = params["payload"]
    message_payload = payload["payload"]

    # The msgId we send as part of payload is received back as `id`, which we
    # later use to determine the next node to run
    interactive_content = message_payload |> Map.merge(%{"id" => message_payload["id"]})

    %{
      bsp_message_id: payload["id"],
      context_id: context_id(payload),
      body: message_payload["title"],
      interactive_content: interactive_content,
      sender: %{
        phone: payload["sender"]["phone"],
        name: payload["sender"]["name"]
      }
    }
  end

  @doc false
  @spec receive_whatsapp_form_response({map(), map(), String.t()}) :: map()
  def receive_whatsapp_form_response({message, contact, template_id}) do
    %{
      bsp_message_id: message["id"],
      body: "",
      context_id: context_id(message),
      raw_response: message["interactive"]["nfm_reply"]["response_json"],
      submitted_at: message["timestamp"],
      template_id: template_id,
      sender: %{
        phone: contact["wa_id"],
        name: contact["profile"]["name"]
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

  @max_size 4096
  @spec check_size(map()) :: map()
  defp check_size(%{text: text} = attrs) do
    if String.length(text) < @max_size,
      do: attrs,
      else: attrs |> Map.merge(%{error: "Message size greater than #{@max_size} characters"})
  end

  defp check_size(%{caption: caption} = attrs) do
    if String.length(caption) < @max_size,
      do: attrs,
      else: attrs |> Map.merge(%{error: "Message size greater than #{@max_size} characters"})
  end

  @doc false
  @spec send_message(map(), Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  defp send_message(%{error: error} = _payload, _message, _attrs), do: {:error, error}

  defp send_message(payload, message, attrs) do
    # sending the node reference also with message, so that we can track when we
    # receive the response incase of a particular message
    payload = Map.put(payload, "msgid", message.uuid)

    request_body =
      %{"channel" => @channel}
      |> Map.merge(format_sender(message))
      |> Map.put(:destination, message.receiver.phone)
      |> Map.put("message", Jason.encode!(payload))

    ## gupshup does not allow null in the caption.
    attrs =
      if Map.has_key?(attrs, :caption) and is_nil(attrs[:caption]),
        do: Map.put(attrs, :caption, ""),
        else: attrs

    create_oban_job(message, request_body, attrs)
  end

  @doc false
  @spec to_minimal_map(map()) :: map()
  defp to_minimal_map(attrs) do
    Map.take(attrs, [:params, :template_id, :template_uuid, :is_hsm, :template_type])
  end

  @spec create_oban_job(Message.t(), map(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  defp create_oban_job(message, request_body, attrs) do
    attrs = to_minimal_map(attrs)
    worker_module = Communications.provider_worker(message.organization_id)
    worker_args = %{message: Message.to_minimal_map(message), payload: request_body, attrs: attrs}

    worker_module.create_changeset(worker_args, scheduled_at: message.send_at)
    |> Oban.insert()
  end
end
