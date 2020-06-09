defmodule Glific.Communications.Message do
  alias Glific.Messages
  alias Glific.Messages.Message
  alias Glific.Contacts

  defmacro __using__(_opts \\ []) do
    quote do
    end
  end

  def send_message(%Message{type: :text} = message) do
    message
    |> send_text()
  end

  def send_message(message) do
    message
    |> send_media()
  end

  defp send_text(message) do
    provider_module()
    |> apply(:send_text, [message])
  end

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

      :document ->
        provider_module()
        |> apply(:send_document, [message])
    end
  end

  def provider_module() do
    provider = Glific.Communications.effective_provider()
    String.to_existing_atom(to_string(provider) <> ".Message")
  end

  def organisation_contact() do
    Glific.Communications.organisation_contact()
  end

  def get_receiver_id_for_inbound() do
    # TODO: Make this dynamic
    1
  end
end
