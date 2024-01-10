defmodule Glific.Providers.Maytapi.Message do
  @moduledoc """
  Message API layer between application and Maytapi
  """

  alias Providers.Maytapi.ApiClient

  @doc false
  def send_text(org_id, attrs) do
    send_message(org_id, attrs)
  end

  defp send_message(org_id, attrs) do
    payload =
      %{"type" => "text"}
      |> Map.put("to_number", attrs.phone)
      |> Map.put("message", attrs.message)

    ApiClient.send_message(org_id, payload)
  end

  def receive_text(params) do
    IO.inspect(params)
  end
end
