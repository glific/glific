defmodule Glific.Providers.Maytapi.Message do
  @moduledoc """
  Message API layer between application and Maytapi
  """

  import Ecto.Query, warn: false

  alias Glific.Partners

  alias Glific.{
    Communications.MessageMaytapi,
    Contacts,
    Repo,
    WAGroup.WAManagedPhone,
    WAMessages,
    Groups.WAGroup
  }

  @doc false
  @spec create_and_send_message(map(), map()) :: any()
  def create_and_send_message(user, attrs) do
    {:ok, contact} = Repo.fetch_by(WAManagedPhone, phone: attrs.wa_managed_phone)

    contact
    |> Map.put(:name, user.name)
    |> Map.drop([:__meta__, :__struct__])
    |> Contacts.maybe_create_contact()

    message =
      %{
        body: attrs.message,
        type: "text",
        contact_id: Partners.organization_contact_id(user.organization_id),
        organization_id: user.organization_id,
        message_type: "WA",
        bsp_status: "sent",
        wa_group_id: get_group_id(attrs),
        wa_managed_phone_id: get_wa_managed_phone_id(attrs),
        bsp_id: attrs.wa_group_id,
        send_at: DateTime.utc_now()
      }
      |> WAMessages.create_message()

    MessageMaytapi.send_message(message, contact)
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

  @spec get_group_id(map()) :: non_neg_integer()
  defp get_group_id(attrs) do
    WAGroup
    |> where([g], g.bsp_id == ^attrs.wa_group_id)
    |> select([g], g.id)
    |> Repo.one!()
  end

  @spec get_wa_managed_phone_id(map()) :: non_neg_integer()
  defp get_wa_managed_phone_id(attrs) do
    WAManagedPhone
    |> where([wg], wg.phone == ^attrs.wa_managed_phone)
    |> select([wg], wg.id)
    |> Repo.one!()
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
