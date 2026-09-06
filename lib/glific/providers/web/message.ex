defmodule Glific.Providers.Web.Message do
  @moduledoc """
  Outbound adapter for the web channel: delivers a staff reply to the browser over the contact's
  Phoenix channel instead of to a WhatsApp BSP.

  Implements the same token functions as the BSP message modules so
  `Glific.Communications.Message.send_message/2` can dispatch to it without special-casing every
  message type — but it is not a `Glific.Providers.MessageBehaviour`: that behaviour also covers
  inbound webhook parsing, and the web channel has no webhooks. Inbound lives in
  `Glific.Communications.WebMessage`.

  Delivery is best effort by design. If the contact has no socket open the message is still
  persisted and still appears in the staff inbox; the widget picks it up from the history it
  fetches on its next join. There is no offline queue and no delivery receipt, so a web message
  never becomes `:delivered`.
  """

  alias Glific.{
    Messages,
    Messages.Message,
    Repo
  }

  alias GlificWeb.WebChannel.MessageSerializer

  @doc false
  @spec send_text(Message.t(), map()) :: {:ok, Message.t()} | {:error, String.t()}
  def send_text(message, _attrs \\ %{}), do: deliver(message)

  @doc false
  @spec send_image(Message.t(), map()) :: {:ok, Message.t()} | {:error, String.t()}
  def send_image(message, _attrs \\ %{}), do: deliver(message)

  @doc false
  @spec send_audio(Message.t(), map()) :: {:ok, Message.t()} | {:error, String.t()}
  def send_audio(message, _attrs \\ %{}), do: deliver(message)

  @doc false
  @spec send_video(Message.t(), map()) :: {:ok, Message.t()} | {:error, String.t()}
  def send_video(message, _attrs \\ %{}), do: deliver(message)

  @doc false
  @spec send_document(Message.t(), map()) :: {:ok, Message.t()} | {:error, String.t()}
  def send_document(message, _attrs \\ %{}), do: deliver(message)

  @doc false
  @spec send_sticker(Message.t(), map()) :: {:ok, Message.t()} | {:error, String.t()}
  def send_sticker(message, _attrs \\ %{}), do: deliver(message)

  @doc false
  @spec send_interactive(Message.t(), map()) :: {:ok, Message.t()} | {:error, String.t()}
  def send_interactive(message, _attrs \\ %{}), do: deliver(message)

  @spec deliver(Message.t()) :: {:ok, Message.t()} | {:error, String.t()}
  defp deliver(message) do
    with {:ok, sent} <- mark_sent(message) do
      sent
      |> Repo.preload(:media)
      |> broadcast()

      {:ok, sent}
    end
  end

  # `:sent` and not `:delivered`: nothing on this channel acknowledges receipt, and claiming
  # delivery for a message pushed at a socket that may not be open would be a lie the inbox
  # then shows to staff.
  @spec mark_sent(Message.t()) :: {:ok, Message.t()} | {:error, String.t()}
  defp mark_sent(message) do
    case Messages.update_message(message, %{
           bsp_status: :sent,
           status: :sent,
           sent_at: DateTime.truncate(DateTime.utc_now(), :second)
         }) do
      {:ok, sent} -> {:ok, sent}
      {:error, changeset} -> {:error, Glific.SafeLog.safe_inspect(changeset.errors)}
    end
  end

  @spec broadcast(Message.t()) :: :ok
  defp broadcast(message) do
    GlificWeb.Endpoint.broadcast(
      "web_channel:#{message.receiver_id}",
      "new_message",
      MessageSerializer.serialize(message)
    )
  end
end
