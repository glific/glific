defmodule Glific.Providers.Maytapi.Message do
  @moduledoc """
  Message API layer between application and Maytapi
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Communications.GroupMessage,
    Groups.WAGroup,
    WAGroup.WAManagedPhone,
    WAMessages
  }

  @doc false
  @spec create_and_send_wa_message(WAManagedPhone.t(), WAGroup.t(), map()) :: any()
  def create_and_send_wa_message(wa_phone, wa_group, attrs) do
    {:ok, message} =
      attrs
      |> Map.put_new(:type, :text)
      |> Map.merge(%{
        body: Map.get(attrs, :message),
        contact_id: wa_phone.contact_id,
        organization_id: wa_phone.organization_id,
        message_type: "WA",
        bsp_status: "sent",
        wa_group_id: wa_group.id,
        wa_managed_phone_id: wa_phone.id,
        send_at: DateTime.utc_now()
      })
      |> WAMessages.create_message()

    GroupMessage.send_message(message, %{
      wa_group_bsp_id: wa_group.bsp_id,
      phone_id: wa_phone.phone_id,
      phone: wa_phone.phone
    })
  end

  @doc false
  @spec receive_text(payload :: map()) :: map()
  def receive_text(%{"message" => %{"fromMe" => from_me}} = params) do
    payload = params["message"]

    :ok = validate_phone_number(params["user"]["phone"], payload)
    {flow, status} = if from_me, do: {:outbound, :sent}, else: {:inbound, :received}

    %{
      bsp_id: payload["id"],
      body: payload["text"],
      sender: %{
        phone: params["user"]["phone"],
        name: params["user"]["name"]
      },
      flow: flow,
      status: status
    }
  end

  @doc false
  @spec receive_media(map()) :: map()
  def receive_media(%{"message" => %{"fromMe" => from_me}} = params) do
    payload = params["message"]

    :ok = validate_phone_number(params["user"]["phone"], payload)
    {flow, status} = if from_me, do: {:outbound, :sent}, else: {:inbound, :received}

    %{
      bsp_id: payload["id"],
      caption: payload["caption"],
      url: payload["url"],
      content_type: payload["type"],
      source_url: payload["url"],
      sender: %{
        phone: params["user"]["phone"],
        name: params["user"]["name"]
      },
      flow: flow,
      status: status
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
