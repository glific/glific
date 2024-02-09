defmodule Glific.Providers.Maytapi.Message do
  @moduledoc """
  Message API layer between application and Maytapi
  """

  alias Glific.Providers.Maytapi.ApiClient

  @doc false
  @spec send_text(non_neg_integer, map()) :: any()
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

  @doc false
  @spec receive_text(payload :: map()) :: map()
  def receive_text(params) do
    payload = params["message"]

    # lets ensure that we have a phone number
    # sometime the maytapi payload has a blank payload
    # or maybe a simulator or some test code
    if params["user"]["phone"] in [nil, ""] do
      error = "Phone number is blank, #{inspect(payload)}"
      Glific.log_error(error)
      raise(RuntimeError, message: error)
    end

    %{
      bsp_message_id: payload["id"],
      body: payload["text"],
      sender: %{
        phone: params["user"]["phone"],
        name: params["user"]["name"]
      }
    }
  end

  @doc false
  @spec receive_media(map()) :: map()
  def receive_media(params) do
    payload = params["message"]

    %{
      bsp_message_id: payload["id"],
      caption: payload["caption"],
      url: payload["url"],
      content_type: payload["type"],
      source_url: payload["url"],
      sender: %{
        phone: params["user"]["phone"],
        name: params["user"]["name"]
      }
    }
  end
end
