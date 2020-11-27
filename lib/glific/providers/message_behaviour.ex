defmodule Glific.Providers.MessageBehaviour do
  @moduledoc """
  The message behaviour which all the providers needs to implement for communication
  """

  @callback send_text(message :: Glific.Messages.Message.t()) ::
              {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}

  @callback send_image(message :: Glific.Messages.Message.t()) ::
              {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}

  @callback send_audio(message :: Glific.Messages.Message.t()) ::
              {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}

  @callback send_video(message :: Glific.Messages.Message.t()) ::
              {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}

  @callback send_document(message :: Glific.Messages.Message.t()) ::
              {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}

  @callback send_sticker(message :: Glific.Messages.Message.t()) ::
              {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}

  @callback receive_text(payload :: map()) :: map()

  @callback receive_media(payload :: map()) :: map()

  @callback receive_location(payload :: map()) :: map()
end
