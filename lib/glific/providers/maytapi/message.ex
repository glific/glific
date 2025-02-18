defmodule Glific.Providers.Maytapi.Message do
  @moduledoc """
  Message API layer between application and Maytapi
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Communications,
    Communications.GroupMessage,
    Groups.Group,
    Groups.WAGroup,
    Groups.WAGroupsCollection,
    Groups.WaGroupsCollections,
    Repo,
    WAGroup.WAManagedPhone,
    WAGroup.WAMessage,
    WAGroup.WaPoll,
    WAMessages
  }

  @doc false
  @spec create_and_send_wa_message(WAManagedPhone.t(), WAGroup.t(), map()) ::
          {:ok, WAMessage.t()} | {:error, any()}
  def create_and_send_wa_message(wa_phone, wa_group, attrs) do
    with {:ok, {attrs, poll}} <- add_poll_details(attrs),
         {:ok, message} <- create_wa_message(attrs, wa_phone, wa_group) do
      GroupMessage.send_message(message, %{
        wa_group_bsp_id: wa_group.bsp_id,
        phone_id: wa_phone.phone_id,
        phone: wa_phone.phone,
        poll: poll
      })
    end
  end

  defp create_wa_message(attrs, wa_phone, wa_group) do
    attrs
    |> Map.put_new(:type, :text)
    |> Map.merge(%{
      body: Map.get(attrs, :message),
      contact_id: wa_phone.contact_id,
      organization_id: wa_phone.organization_id,
      bsp_status: "sent",
      wa_group_id: wa_group.id,
      wa_managed_phone_id: wa_phone.id,
      send_at: DateTime.utc_now()
    })
    |> WAMessages.create_message()
  end

  @spec add_poll_details(map()) :: {:ok, {map(), WaPoll.t() | nil}} | {:error, any()}
  defp add_poll_details(%{poll_id: poll_id} = attrs) when not is_nil(poll_id) do
    with {:ok, poll} <- Repo.fetch(WaPoll, poll_id) do
      {:ok,
       {Map.merge(attrs, %{
          poll_id: poll_id,
          poll_content: poll.poll_content,
          message: poll.poll_content["text"],
          type: :poll
        }), poll}}
    end
  end

  defp add_poll_details(attrs), do: {:ok, {attrs, nil}}

  @doc """
  Send message to wa_group collection
  """
  @spec send_message_to_wa_group_collection(Group.t(), map()) :: {:ok, map()}
  def send_message_to_wa_group_collection(group, attrs) do
    wa_group_collections =
      WaGroupsCollections.list_wa_groups_collection(%{
        filter: %{group_id: group.id, organization_id: group.organization_id}
      })
      |> Repo.preload([:wa_group])

    case wa_group_collections do
      [] ->
        {:error, "Cannot send message: No WhatsApp group found in the collection"}

      _ ->
        create_wa_group_message(wa_group_collections, group, attrs)

        # Using Async instead of going with the route of message broadcast as the number of WA groups
        #  per collection will be way less than contacts in a collection
        Task.async_stream(
          wa_group_collections,
          fn wa_group_collection ->
            Repo.put_process_state(wa_group_collection.organization_id)

            {:ok, wa_managed_phone} =
              Repo.fetch_by(WAManagedPhone, %{
                id: wa_group_collection.wa_group.wa_managed_phone_id,
                organization_id: wa_group_collection.organization_id
              })

            create_and_send_wa_message(
              wa_managed_phone,
              wa_group_collection.wa_group,
              Map.delete(attrs, :group_id)
            )
          end,
          max_concurrency: 20,
          on_timeout: :kill_task
        )
        |> Stream.run()

        {:ok, %{success: true}}
    end
  end

  @spec create_wa_group_message([WAGroupsCollection.t()], Group.t(), map()) :: any()
  defp create_wa_group_message([wa_group_collection | _wa_groups], group, attrs) do
    {:ok, wa_managed_phone} =
      Repo.fetch_by(WAManagedPhone, %{
        id: wa_group_collection.wa_group.wa_managed_phone_id,
        organization_id: group.organization_id
      })

    attrs
    |> Map.put_new(:type, :text)
    |> Map.merge(%{
      body: Map.get(attrs, :message),
      contact_id: wa_managed_phone.contact_id,
      organization_id: group.organization_id,
      bsp_status: :enqueued,
      group_id: group.id,
      flow: :outbound,
      send_at: DateTime.utc_now()
    })
    |> WAMessages.create_message()
    |> then(fn {:ok, wa_message} -> wa_group_message_subscription(wa_message) end)
  end

  @spec wa_group_message_subscription(WAMessage.t()) :: any()
  defp wa_group_message_subscription(wa_message) do
    Communications.publish_data(
      wa_message,
      :sent_wa_group_collection_message,
      wa_message.organization_id
    )
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

  @doc false
  @spec receive_location(map()) :: map()
  def receive_location(%{"message" => %{"fromMe" => from_me}} = params) do
    payload = params["message"]

    :ok = validate_phone_number(params["user"]["phone"], payload)
    {flow, status} = if from_me, do: {:outbound, :sent}, else: {:inbound, :received}

    [latitude, longitude] = payload["payload"] |> String.split(",")

    %{
      bsp_id: payload["id"],
      longitude: longitude,
      latitude: latitude,
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

  @doc false
  @spec receive_poll(map()) :: map()
  def receive_poll(%{"message" => %{"fromMe" => from_me}} = params) do
    payload = params["message"]

    {flow, status} = if from_me, do: {:outbound, :sent}, else: {:inbound, :received}

    poll_content = %{
      "text" => payload["text"],
      "options" => payload["options"]
    }

    %{
      bsp_id: payload["id"],
      body: payload["text"],
      poll_content: poll_content,
      type: payload["type"],
      sender: %{
        phone: params["user"]["phone"],
        name: params["user"]["name"]
      },
      flow: flow,
      status: status
    }
  end
end
