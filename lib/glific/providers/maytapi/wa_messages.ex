defmodule Glific.Providers.Maytapi.WaMessages do
  alias Glific.{
    Providers.Gupshup.Message
  }

  @channel  "whatsapp"
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

  defp send_message(payload, message, attrs) do
    request_body =
      %{"channel" => @channel}
      |> Map.merge(Message.format_sender(message))
      |> Map.put(:destination, message.receiver.phone)
      |> Map.put("message", Jason.encode!(payload))

    create_oban_job(message, request_body, attrs)
  end

  @spec create_oban_job(Message.t(), map(), map()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  defp create_oban_job(message, request_body, attrs) do
    IO.inspect(message)

  end
end
