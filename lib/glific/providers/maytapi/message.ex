defmodule Glific.Providers.Maytapi.Message do
  @moduledoc """
  Message API layer between application and Maytapi
  """

  import Ecto.Query, warn: false

  alias Glific.Partners

  alias Glific.{
    Contacts.Contact,
    Providers.Maytapi.ApiClient,
    Repo,
    WAGroup.WAManagedPhone
  }

  @doc false
  @spec send_text(non_neg_integer, map()) :: any()
  def send_text(org_id, attrs) do
    phone_id = get_phone_id(attrs)

    payload =
      %{"type" => "text"}
      |> Map.put("to_number", attrs.phone)
      |> Map.put("message", attrs.message)

    with {:ok, _response} <- ApiClient.send_message(org_id, payload, phone_id) do
      create_message_after_send(org_id, attrs)
    end
  end

  @doc false
  @spec send_text_in_group(non_neg_integer, map()) :: any()
  def send_text_in_group(org_id, attrs) do
    phone_id = get_phone_id(attrs)

    payload =
      %{"type" => "text"}
      |> Map.put("to_number", attrs.bsp_id)
      |> Map.put("message", attrs.message)

    with {:ok, _response} <- ApiClient.send_message(org_id, payload, phone_id) do
      create_message_after_send(org_id, attrs)
    end
  end

  @doc false
  @spec receive_text(payload :: map()) :: map()
  def receive_text(params) do
    payload = params["message"]

    :ok = validate_phone_number(params["user"]["phone"], payload)

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

    :ok = validate_phone_number(params["user"]["phone"], payload)

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

  # lets ensure that we have a phone number
  # sometime the maytapi payload has a blank payload
  # or maybe a simulator or some test code
  @spec validate_phone_number(String.t(), map()) :: :ok | RuntimeError
  defp validate_phone_number(phone, payload) when phone in [nil, ""] do
    error = "Phone number is blank, #{inspect(payload)}"
    Glific.log_error(error)
    raise(RuntimeError, message: error)
  end

  defp validate_phone_number(_phone, _payload), do: :ok
end
