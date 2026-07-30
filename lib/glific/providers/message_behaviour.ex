defmodule Glific.Providers.MessageBehaviour do
  @moduledoc """
  The message behaviour which all the providers needs to implement for communication

  Send callbacks return a union of `{:ok, Oban.Job.t()}` (BSP-backed channels like Gupshup/
  Maytapi, which enqueue an async delivery job) and `{:ok, Glific.Messages.Message.t()}`
  (synchronous-delivery channels, e.g. the web channel, which deliver over a live socket with
  no job queue). Implementations only ever return the member(s) of the union that match how
  they actually deliver — the union just lets both delivery models share one behaviour.
  """

  @callback send_text(
              message :: Glific.Messages.Message.t(),
              attrs :: map()
            ) ::
              {:ok, Oban.Job.t()}
              | {:ok, Glific.Messages.Message.t()}
              | {:error, Ecto.Changeset.t()}
              | {:error, String.t()}

  @callback send_image(message :: Glific.Messages.Message.t(), attrs :: map()) ::
              {:ok, Oban.Job.t()}
              | {:ok, Glific.Messages.Message.t()}
              | {:error, Ecto.Changeset.t()}
              | {:error, String.t()}

  @callback send_audio(message :: Glific.Messages.Message.t(), attrs :: map()) ::
              {:ok, Oban.Job.t()}
              | {:ok, Glific.Messages.Message.t()}
              | {:error, Ecto.Changeset.t()}

  @callback send_video(message :: Glific.Messages.Message.t(), attrs :: map()) ::
              {:ok, Oban.Job.t()}
              | {:ok, Glific.Messages.Message.t()}
              | {:error, Ecto.Changeset.t()}
              | {:error, String.t()}

  @callback send_document(message :: Glific.Messages.Message.t(), attrs :: map()) ::
              {:ok, Oban.Job.t()}
              | {:ok, Glific.Messages.Message.t()}
              | {:error, Ecto.Changeset.t()}

  @callback send_sticker(message :: Glific.Messages.Message.t(), attrs :: map()) ::
              {:ok, Oban.Job.t()}
              | {:ok, Glific.Messages.Message.t()}
              | {:error, Ecto.Changeset.t()}
              | {:error, String.t()}

  @callback send_interactive(message :: Glific.Messages.Message.t(), attrs :: map()) ::
              {:ok, Oban.Job.t()}
              | {:ok, Glific.Messages.Message.t()}
              | {:error, Ecto.Changeset.t()}
              | {:error, String.t()}

  @callback receive_text(payload :: map()) :: map()

  @callback receive_media(payload :: map()) :: map()

  @callback receive_location(payload :: map()) :: map()

  @callback receive_interactive(payload :: map()) :: map()

  @callback receive_billing_event(payload :: map()) :: {:ok, map()} | {:error, String.t()}
end
