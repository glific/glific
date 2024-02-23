defmodule Glific.Providers.Maytapi.WAMessages do
  @moduledoc """
  Message API layer between application and maytapi
  """

  alias Glific.{
    Providers.Maytapi.WAWorker,
    WAGroup.WAMessage
  }

  @doc false
  @spec send_text(WAMessage.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  def send_text(message, attrs) do
    %{type: :text, message: message.body}
    |> check_size()
    |> send_message(message, attrs)
  end

  @doc false
  def send_image(message, attrs \\ %{}) do
    message_media = message.media

    payload =
      %{
        message: message_media.source_url,
        type: "image"
      }
      |> Map.put_new(:text, message_media.caption || "")
      |> check_size_of_caption()

    send_message(payload, message, attrs)
  end

  @doc false
  @spec format_sender(WAMessage.t(), map()) :: map()
  defp format_sender(message, attrs) do
    %{
      "to_number" => attrs.wa_group_bsp_id,
      "phone" => attrs.phone,
      "type" => message.type
    }
  end

  @max_size 6000
  @doc false
  @spec check_size(map()) :: map()
  defp check_size(%{message: text} = attrs) do
    if String.length(text) < @max_size,
      do: attrs,
      else: attrs |> Map.merge(%{error: "Message size greater than #{@max_size} characters"})
  end

  defp check_size_of_caption(%{text: caption} = attrs) do
    if String.length(caption) < @max_size,
      do: attrs,
      else: attrs |> Map.merge(%{error: "Message size greater than #{@max_size} characters"})
  end

  @doc false
  @spec send_message(map(), WAMessage.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  defp send_message(%{error: error} = _payload, _message, _attrs), do: {:error, error}

  defp send_message(payload, message, attrs) do
    request_body =
      format_sender(message, attrs)
      |> Map.put("phone_id", attrs.phone_id)
      |> Map.put("message", payload.message)

    if Map.has_key?(payload, :text) && payload.text != "" do
      request_body = Map.put(request_body, "text", payload.text)
    end

    create_oban_job(message, request_body)
  end

  @doc false
  @spec create_oban_job(WAMessage.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  defp create_oban_job(message, request_body) do
    worker_args =
      %{
        message: WAMessage.to_minimal_map(message),
        payload: request_body
      }

    WAWorker.new(worker_args, scheduled_at: message.send_at)
    |> Oban.insert()
  end
end
