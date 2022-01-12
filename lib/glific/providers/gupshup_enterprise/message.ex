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
  @spec caption(nil | String.t()) :: String.t()
  defp caption(nil), do: ""
  defp caption(caption), do: caption

  @max_size 4096
  @doc false
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

  @doc false
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
