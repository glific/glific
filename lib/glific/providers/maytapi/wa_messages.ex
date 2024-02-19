defmodule Glific.Providers.Maytapi.WaMessages do
  alias Glific.Messages.Message

  alias Glific.{
    Providers.Gupshup.Message
  }

  @doc false
  @spec format_sender(Message.t(), map()) :: map()
  defp format_sender(message, attrs) do
    %{
      "to_number" => message.bsp_message_id,
      "message" => message.body,
      "type" => message.type,
      "phone" => attrs.phone
    }
  end

  @doc false
  def send_text(message, attrs \\ %{}) do
    %{type: :text, text: message.body}
    |> Message.check_size()
    |> send_message(message, attrs)
  end

  @doc false
  @spec send_message(map(), Message.t(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  defp send_message(%{error: error} = _payload, _message, _attrs), do: {:error, error}

  defp send_message(_payload, message, attrs) do
    request_body =
      format_sender(message, attrs)
      |> Map.put("phone_id", attrs.phone_id)

    create_oban_job(message, request_body, attrs)
  end

  @doc false
  @spec to_minimal_map(map()) :: map()
  defp to_minimal_map(attrs) do
    Map.take(attrs, [:params, :is_hsm])
  end

  @spec create_oban_job(Message.t(), map(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  defp create_oban_job(message, request_body, attrs) do
    attrs = to_minimal_map(attrs)
    worker_module = Glific.Providers.Maytapi.WaWorker

    worker_args =
      %{
        message: Glific.Messages.Message.to_minimal_map(message),
        payload: request_body,
        attrs: attrs
      }
    worker_module.new(worker_args, schedule_in: 1)
    |> Oban.insert()
  end
end
