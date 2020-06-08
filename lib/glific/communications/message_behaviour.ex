defmodule Glific.Communications.MessageBehaviour do
  @doc """
  Invoked when a request runs.

  ## Arguments

  - `payload` - payload for the event
  - `destination` - destination number for communication
  """

  @callback send_text(message :: Glific.Messages.Message.t()) ::
              {:ok, response :: map()} | {:error, message :: String.t()}

  @callback send_image(message :: Glific.Messages.Message.t()) ::
              {:ok, response :: map()} | {:error, message :: String.t()}

  @callback send_audio(message :: Glific.Messages.Message.t()) ::
              {:ok, response :: map()} | {:error, message :: String.t()}

  @callback send_video(message :: Glific.Messages.MessageMedia.t()) ::
              {:ok, response :: map()} | {:error, message :: String.t()}

  @callback send_document(message :: Glific.Messages.MessageMedia.t()) ::
              {:ok, response :: map()} | {:error, message :: String.t()}

  @callback receive_text(payload :: map()) ::
              {message :: map(), contact :: map()}

  @callback receive_media(payload :: map()) ::
              {message :: map(), contact :: map()}
end
