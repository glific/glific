defmodule Glific.Providers.Maytapi.WAMessages do
  @moduledoc """
  Message API layer between application and maytapi
  """

  alias Glific.Messages.Message

  @doc false
  @spec send_text(Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  def send_text(message, attrs \\ %{}) do
    %{type: :text, text: message.body}
    |> Glific.Providers.Gupshup.Message.check_size()
    |> send_message(message, attrs)
  end

  @doc false
  @spec format_sender(Message.t(), map()) :: map()
  defp format_sender(message, attrs) do
    %{
      "to_number" => message.wa_group_id,
      "message" => message.body,
      "type" => message.type,
      "phone" => attrs.phone
    }
  end

  @doc false
  @spec send_message(map(), Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  defp send_message(%{error: error} = _payload, _message, _attrs), do: {:error, error}

  defp send_message(_payload, message, attrs) do
    request_body =
      format_sender(message, attrs)
      |> Map.put("phone_id", attrs.phone_id)

    create_oban_job(message, request_body)
  end

  @doc false
  @spec create_oban_job(Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  defp create_oban_job(message, request_body) do
    worker_module = Glific.Providers.Maytapi.WaWorker

    worker_args =
      %{
        message: Glific.Messages.Message.to_minimal_map(message),
        payload: request_body
      }

    worker_module.new(worker_args, scheduled_at: message.send_at)
    |> Oban.insert()
  end
end
