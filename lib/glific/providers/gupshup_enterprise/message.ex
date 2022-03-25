defmodule Glific.Providers.Gupshup.Enterprise.Message do
  @moduledoc """
  Message API layer between application and Gupshup
  """

  alias Glific.{
    Communications,
    Messages.Message
  }

  require Logger

  @doc false
  @spec send_text(Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  def send_text(message, attrs \\ %{}) do
    %{msg_type: :DATA_TEXT, msg: message.body}
    |> check_size()
    |> send_message(message, attrs)
  end

  @doc false
  @spec send_video(Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  def send_video(message, attrs \\ %{}) do
    %{
      msg_type: :VIDEO,
      media_url: message.media.source_url,
      caption: caption(message.media.caption)
    }
    |> check_size()
    |> send_message(message, attrs)
  end

  @doc false
  @spec send_audio(Message.t(), map()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_audio(message, attrs \\ %{}) do
    %{
      msg_type: :AUDIO,
      media_url: message.media.source_url
    }
    |> send_message(message, attrs)
  end

  @doc false
  @spec send_image(Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  def send_image(message, attrs \\ %{}) do
    %{
      msg_type: :IMAGE,
      media_url: message.media.source_url,
      caption: caption(message.media.caption)
    }
    |> check_size()
    |> send_message(message, attrs)
  end

  @doc false
  @spec send_document(Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_document(message, attrs \\ %{}) do
    %{
      msg_type: :DOCUMENT,
      media_url: message.media.source_url,
      caption: message.media.caption
    }
    |> send_message(message, attrs)
  end

  @doc false
  @spec send_interactive(Message.t(), map()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def send_interactive(message, attrs) do
    interactive_content = parse_interactive_message(attrs.interactive_content)

    %{
      interactive_content: interactive_content,
      msg: message.body,
      interactive_type: message.type
    }
    |> send_message(message, attrs)
  end

  @spec parse_interactive_message(map()) :: map()
  defp parse_interactive_message(interactive_content) do
    %{
      "button" => interactive_content["globalButtons"] |> List.first() |> Map.get("title"),
      "sections" => parse_section(interactive_content["items"])
    }
  end

  @spec parse_interactive_message(list()) :: list()
  def parse_section(items),
    do: Enum.reduce(items, [], fn item, acc -> acc ++ do_parse_section(item) end)

  @spec do_parse_section(list()) :: list()
  defp do_parse_section(item),
    do: [%{"title" => item["title"], "rows" => parse_rows(item["options"])}]

  @spec parse_rows(list()) :: list()
  defp parse_rows(rows) do
    Enum.reduce(rows, [], fn row, acc ->
      acc ++
        [
          %{
            # repeating row["title"] as we dont actually store id in Glific
            "id" => row["title"],
            "title" => row["title"],
            "description" => row["description"]
          }
        ]
    end)
  end

  @spec caption(nil | String.t()) :: String.t()
  defp caption(nil), do: ""
  defp caption(caption), do: caption

  @max_size 4096

  @spec check_size(map()) :: map()
  defp check_size(%{msg: text} = attrs) do
    if String.length(text) < @max_size,
      do: attrs,
      else: attrs |> Map.merge(%{error: "Message size greater than #{@max_size} characters"})
  end

  defp check_size(%{caption: caption} = attrs) do
    if String.length(caption) < @max_size,
      do: attrs,
      else: attrs |> Map.merge(%{error: "Message size greater than #{@max_size} characters"})
  end

  @spec send_message(map(), Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  defp send_message(%{error: error} = _payload, _message, _attrs), do: {:error, error}

  defp send_message(payload, message, attrs) do
    ## gupshup does not allow null in the caption.
    attrs =
      if Map.has_key?(attrs, :caption) and is_nil(attrs[:caption]),
        do: Map.put(attrs, :caption, ""),
        else: attrs

    %{"send_to" => message.receiver.phone, "message" => Jason.encode!(payload)}
    |> then(&create_oban_job(message, &1, attrs))
  end

  @doc false
  @spec receive_text(payload :: map()) :: map()
  def receive_text(params) do
    # lets ensure that we have a phone number
    # sometime the gupshup payload has a blank payload
    # or maybe a simulator or some test code
    if is_nil(params["mobile"]) ||
         String.trim(params["mobile"]) == "" do
      error = "Phone number is blank, #{inspect(params)}"
      Logger.error(error)

      stacktrace =
        self()
        |> Process.info(:current_stacktrace)
        |> elem(1)

      Appsignal.send_error(:error, error, stacktrace)
      raise(RuntimeError, message: error)
    end

    %{
      bsp_message_id: params["replyId"],
      context_id: params["replyId"] <> "-" <> params["messageId"],
      body: params["text"],
      sender: %{
        phone: params["mobile"],
        name: params["name"]
      }
    }
  end

  @doc false
  @spec receive_media(map()) :: map()
  def receive_media(params) do
    message_payload = get_message_payload(params["type"], params)

    %{
      bsp_message_id: params["replyId"],
      context_id: params["messageId"],
      caption: message_payload["caption"],
      url: message_payload["url"] <> message_payload["signature"],
      source_url: message_payload["url"] <> message_payload["signature"],
      sender: %{
        phone: params["mobile"],
        name: params["name"]
      }
    }
  end

  defp get_message_payload("image", params), do: Jason.decode!(params["image"])
  defp get_message_payload("video", params), do: Jason.decode!(params["video"])
  defp get_message_payload("audio", params), do: Jason.decode!(params["audio"])
  defp get_message_payload("document", params), do: Jason.decode!(params["document"])

  @doc false
  @spec receive_location(map()) :: map()
  def receive_location(params) do
    location = Jason.decode!(params["location"])

    %{
      bsp_message_id: params["replyId"],
      context_id: params["messageId"],
      longitude: location["longitude"],
      latitude: location["latitude"],
      sender: %{
        phone: params["mobile"],
        name: params["name"]
      }
    }
  end

  @spec to_minimal_map(map()) :: map()
  defp to_minimal_map(attrs) do
    Map.take(attrs, [:params, :template_id, :template_uuid, :is_hsm, :template_type, :has_buttons])
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
