defmodule Glific.Communications.MessageMaytapi do
  @moduledoc """
  The Message Communication Context, which encapsulates and manages tags and the related join tables.
  """

  require Logger

  alias Glific.{
    Messages,
    Messages.Message,
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
    document: :send_document,
    sticker: :send_sticker,
    list: :send_interactive,
    quick_reply: :send_interactive,
    location_request_message: :send_interactive
  }

  @doc """
  Send message to receiver using define provider.
  """
  # @spec send_message(, map()) :: {:ok, Message.t()} | {:error, String.t()}
  def send_message({:ok, %Message{} = message}, attrs \\ %{}) do
    message = Repo.preload(message, [:receiver, :sender, :media])

    Logger.info(
      "Sending message: type: '#{message.type}', contact_id: '#{message.receiver.id}', message_id: '#{message.id}'"
    )

    with {:ok, _} <-
           apply(
             Glific.Providers.Maytapi.WaMessages,
             @type_to_token[message.type],
             [message, attrs]
           ) do
      :telemetry.execute(
        [:glific, :message, :sent],
        # currently we are not measuring latency
        %{duration: 1},
        %{
          type: message.type,
          sender_id: message.sender_id,
          receiver_id: message.receiver_id,
          organization_id: message.organization_id
        }
      )
    end
  rescue
    _ ->
      log_error(message, "Could not send message to contact: Check maytapi Setting")
  end

  @spec log_error(Message.t(), String.t()) :: {:error, String.t()}
  defp log_error(message, reason) do
    message = Repo.preload(message, [:receiver])
    Messages.notify(message, reason)

    {:ok, _} = Messages.update_message(message, %{status: :error})
    {:error, reason}
  end
end
