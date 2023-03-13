defmodule Glific.Providers.Airtel.Message do
  @moduledoc """
  Message API layer between application and Airtel
  """

  alias Glific.{
    Communications,
    Messages.Message
  }

  import Ecto.Query, warn: false
  require Logger

  @doc false
  @spec send_text(Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  def send_text(message, attrs \\ %{}) do
    %{type: :text, message: %{:text => message.body}}
    |> send_message(message, attrs)
  end

  @doc false
  @spec send_image(Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  def send_image(message, attrs \\ %{}) do
    message_media = message.media

    %{
      type: :image,
      mediaAttachment: %{
        type: "IMAGE",
        url: message_media.source_url,
        caption: caption(message_media.caption)
      }
    }
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
  @spec add_attachment(map(), map(), atom()) :: map()
  defp add_attachment(interactive, attachment, :quick_reply) do
    case attachment["content"]["type"] do
      "image" ->
        media_attachment = %{
          type: "IMAGE",
          url: attachment["content"]["url"]
        }

        interactive
        |> Map.put(
          "mediaAttachment",
          media_attachment
        )

      _ ->
        interactive
    end
  end

  defp add_attachment(interactive, _attachment, :list), do: interactive

  @spec parse_interactive_message(map(), atom()) :: map()
  defp parse_interactive_message(content, :quick_reply) do
    buttons =
      Enum.map(content["options"], fn x ->
        %{"title" => x["title"], "tag" => x["title"]}
      end)

    %{
      message: %{text: content["content"]["text"]},
      buttons: buttons
    }
  end

  defp parse_interactive_message(content, :list) do
    list_options =
      content["items"]
      |> Enum.at(0)

    options =
      Enum.map(list_options["options"], fn option ->
        %{
          tag: option["title"],
          title: option["title"],
          description: option["description"]
        }
      end)

    heading = content["globalButtons"] |> Enum.at(0)

    %{message: %{text: content["body"]}, list: %{heading: heading["title"], options: options}}
  end

  @doc false
  @spec send_interactive(Message.t(), map()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_interactive(message, attrs \\ %{}) do
    interactive_content = parse_interactive_message(message.interactive_content, message.type)

    content = message.interactive_content

    interactive_content
    |> Map.put(:type, content["type"])
    |> add_attachment(content, message.type)
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
    text = get_in(params, ["message", "text"])

    %{
      bsp_message_id: params["sessionId"],
      body: text["body"],
      sender: %{
        phone: params["from"],
        # we need name here as we are checking it afterwards but we don't receive in payload
        name: ""
      }
    }
  end

  # @doc false
  # @spec receive_media(map()) :: map()
  # def receive_media(params) do
  #   payload = params["payload"]
  #   message_payload = payload["payload"]

  #   %{
  #     bsp_message_id: payload["id"],
  #     context_id: context_id(payload),
  #     caption: message_payload["caption"],
  #     url: message_payload["url"],
  #     source_url: message_payload["url"],
  #     sender: %{
  #       phone: payload["sender"]["phone"],
  #       name: payload["sender"]["name"]
  #     }
  #   }
  # end

  # @doc false
  # @spec receive_location(map()) :: map()
  # def receive_location(params) do
  #   payload = params["payload"]
  #   message_payload = payload["payload"]

  #   %{
  #     bsp_message_id: payload["id"],
  #     context_id: context_id(payload),
  #     longitude: message_payload["longitude"],
  #     latitude: message_payload["latitude"],
  #     sender: %{
  #       phone: payload["sender"]["phone"],
  #       name: payload["sender"]["name"]
  #     }
  #   }
  # end

  # @doc false
  # @spec receive_billing_event(map()) :: {:ok, map()} | {:error, String.t()}
  # def receive_billing_event(params) do
  #   references = get_in(params, ["payload", "references"])
  #   deductions = get_in(params, ["payload", "deductions"])
  #   bsp_message_id = references["gsId"] || references["id"]

  #   message_id =
  #     Repo.fetch_by(Message, %{
  #       bsp_message_id: bsp_message_id
  #     })
  #     |> case do
  #       {:ok, message} -> message.id
  #       {:error, _error} -> nil
  #     end

  #   message_conversation = %{
  #     deduction_type: deductions["type"],
  #     is_billable: deductions["billable"],
  #     conversation_id: references["conversationId"],
  #     payload: params,
  #     message_id: message_id
  #   }

  #   {:ok, message_conversation}
  # end

  @doc false
  @spec receive_interactive(map()) :: map()
  def receive_interactive(params) do
    payload = params["payload"]
    message_payload = payload["payload"]

    ## Airtel does not send an option id back as a response.
    ## They just send the postbackText back as the option id.
    ## formatting that here will help us to keep that consistent.
    ## We might remove this in the future when airtel will start sending the option id.

    interactive_content = message_payload |> Map.merge(%{"id" => message_payload["postbackText"]})

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

  # @doc false
  # @spec format_sender(Message.t()) :: map()
  # defp format_sender(message) do
  #   organization = Partners.organization(message.organization_id)

  #   %{
  #     "source" => message.sender.phone,
  #     "src.name" => organization.services["bsp"].secrets["app_name"]
  #   }
  # end

  # @max_size 4096
  # @doc false
  # @spec check_size(map()) :: map()
  # defp check_size(%{text: text} = attrs) do
  #   if String.length(text) < @max_size,
  #     do: attrs,
  #     else: attrs |> Map.merge(%{error: "Message size greater than #{@max_size} characters"})
  # end

  # defp check_size(%{caption: caption} = attrs) do
  #   if String.length(caption) < @max_size,
  #     do: attrs,
  #     else: attrs |> Map.merge(%{error: "Message size greater than #{@max_size} characters"})
  # end

  @doc false
  @spec send_message(map(), Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  # defp send_message(%{error: error} = _payload, _message, _attrs), do: {:error, error}

  defp send_message(payload, message, attrs) do
    # this is common across all messages
    request_body =
      payload
      |> Map.put(:sessionId, message.uuid)
      |> Map.put(:to, message.receiver.phone)
      |> Map.put(:from, message.sender.phone)

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

    worker_module.new(worker_args, scheduled_at: message.send_at)
    |> Oban.insert()
  end
end
