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

    ApiClient.send_message(org_id, payload, phone_id)
  end

  @doc false
  @spec send_text_in_group(non_neg_integer, map()) :: any()
  def send_text_in_group(org_id, attrs) do
    phone_id = get_phone_id(attrs)

    payload =
      %{"type" => "text"}
      |> Map.put("to_number", attrs.bsp_id)
      |> Map.put("message", attrs.message)

    case ApiClient.send_message(org_id, payload, phone_id) do
      {:ok, response} ->
        message_attrs =
          %{
            body: attrs.message,
            status: "sent",
            type: "text",
            receiver_id: Partners.organization_contact_id(org_id),
            organization_id: org_id,
            sender_id: get_sender_id(attrs),
            bsp_message_id: attrs.bsp_id,
            message_type: "WABA+WA",
            bsp_status: "sent"
          }
          |> Glific.Messages.create_message()
    end
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

  @spec get_phone_id(map()) :: non_neg_integer()
  defp get_phone_id(attrs) do
    WAManagedPhone
    |> where([g], g.phone == ^attrs.phone)
    |> select([g], g.phone_id)
    |> Repo.one!()
  end

  @spec get_sender_id(map()) :: non_neg_integer()
  defp get_sender_id(attrs) do
    Contact
    |> where([g], g.phone == ^attrs.phone)
    |> select([g], g.id)
    |> Repo.one!()
  end
end
