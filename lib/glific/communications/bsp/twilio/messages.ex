defmodule Glific.Communications.BSP.Twilio.Message do
  @behaviour Glific.Communications.MessageBehaviour

  @impl Glific.Communications.MessageBehaviour
  def send_text(_message), do: {:ok, :response}

  @impl Glific.Communications.MessageBehaviour
  def send_image(_message), do: {:ok, :response}

  @impl Glific.Communications.MessageBehaviour
  def send_audio(_message), do: {:ok, :response}

  @impl Glific.Communications.MessageBehaviour
  def send_video(_message), do: {:ok, :response}

  @impl Glific.Communications.MessageBehaviour
  def send_document(_message), do: {:ok, :response}

  @impl Glific.Communications.MessageBehaviour
  def receive_text(_payload), do: {:message, :contact}

  @impl Glific.Communications.MessageBehaviour
  def receive_media(_payload), do: {:message, :contact}
end
