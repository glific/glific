defmodule Glific.Providers.Maytapi.Message do
  @moduledoc """
  Message API layer between application and Maytapi
  """
  require Logger

  alias Glific.{
    Communications,
    Communications.GroupMessage,
    Groups.Group,
    Groups.WAGroup,
    Groups.WAGroupsCollection,
    Groups.WaGroupsCollections,
    Providers.Maytapi.Sender,
    Repo,
    SafeLog,
    WAGroup.WAMessage,
    WAGroup.WaPoll,
    WAMessages
  }

  @doc """
  Pick the managed phone for `wa_group` via `Sender.pick_for_send/2` (so
  primary-with-failover applies), record the outbound `wa_message`, and
  dispatch it through Maytapi.

  Returns `{:ok, %WAMessage{}}` on success, `{:error, :no_active_phones}`
  when the group has no usable phone, `{:error, :promotion_failed}` when
  a failover candidate was found but the primary swap could not be
  persisted, or any error surfaced by the underlying create/send pipeline.
  """
  @spec create_and_send_wa_message(WAGroup.t(), map()) ::
          {:ok, WAMessage.t()} | {:error, any()}
  def create_and_send_wa_message(%WAGroup{} = wa_group, attrs) do
    with {:ok, wa_phone, _source} <- Sender.pick_for_send(wa_group),
         {:ok, {attrs, poll}} <- add_poll_details(attrs),
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
      |> Repo.preload(wa_group: :primary_phone)

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

            result =
              create_and_send_wa_message(
                wa_group_collection.wa_group,
                Map.delete(attrs, :group_id)
              )

            log_collection_send_failure(result, wa_group_collection, group)
            result
          end,
          max_concurrency: 20,
          on_timeout: :kill_task
        )
        |> Stream.run()

        {:ok, %{success: true}}
    end
  end

  @spec log_collection_send_failure(any(), WAGroupsCollection.t(), Group.t()) :: :ok
  defp log_collection_send_failure({:ok, _}, _wa_group_collection, _group), do: :ok

  defp log_collection_send_failure(result, %{wa_group_id: wa_group_id}, %{
         id: group_id,
         organization_id: org_id
       }) do
    Glific.log_error(
      "Maytapi send failed (collection): wa_group=#{SafeLog.safe_inspect(wa_group_id)} group=#{SafeLog.safe_inspect(group_id)} org=#{org_id} result=#{SafeLog.safe_inspect(result)}"
    )

    Appsignal.increment_counter("glific.maytapi.send_failed", 1, %{source: "collection"})
    :ok
  end

  @doc """
  Record a message sent to a group in the wa_message table.
  """

  @spec create_wa_group_message([WAGroupsCollection.t()], Group.t(), map()) :: any()
  def create_wa_group_message(
        [%{wa_group: %{primary_phone: nil} = wa_group} | _rest],
        %{id: group_id, organization_id: org_id} = _group,
        _attrs
      ) do
    Glific.log_error(
      "Maytapi collection: skipping group-level wa_message row (no primary phone) wa_group=#{SafeLog.safe_inspect(wa_group.id)} org=#{org_id} collection=#{SafeLog.safe_inspect(group_id)}"
    )

    {:error, :no_primary_phone}
  end

  def create_wa_group_message([wa_group_collection | _wa_groups], group, attrs) do
    wa_managed_phone = wa_group_collection.wa_group.primary_phone

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
    |> case do
      {:ok, wa_message} ->
        wa_group_message_subscription(wa_message)
        {:ok, wa_message}

      {:error, error} ->
        Glific.log_error(
          "Maytapi collection: group-level wa_message insert failed collection=#{SafeLog.safe_inspect(group.id)} org=#{group.organization_id} error=#{SafeLog.safe_inspect(error)}"
        )

        {:error, error}
    end
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

    {flow, status} = if from_me, do: {:outbound, :sent}, else: {:inbound, :received}

    %{
      bsp_id: payload["id"],
      body: payload["text"],
      sender: %{
        phone: resolve_sender_phone(params),
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

    {flow, status} = if from_me, do: {:outbound, :sent}, else: {:inbound, :received}

    %{
      bsp_id: payload["id"],
      caption: payload["caption"],
      url: payload["url"],
      content_type: payload["type"],
      source_url: payload["url"],
      sender: %{
        phone: resolve_sender_phone(params),
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

    {flow, status} = if from_me, do: {:outbound, :sent}, else: {:inbound, :received}

    [latitude, longitude] = payload["payload"] |> String.split(",")

    %{
      bsp_id: payload["id"],
      longitude: longitude,
      latitude: latitude,
      sender: %{
        phone: resolve_sender_phone(params),
        name: params["user"]["name"]
      },
      flow: flow,
      status: status
    }
  end

  # Maytapi delivers a blank `user.phone` for participants in privacy-enabled
  # (LID) WhatsApp groups. When the participant is a regular `@c.us` user the
  # real number is still present as the trailing segment of the message id, so
  # we recover it from there. A genuine `@lid` participant stays unresolved
  # (nil) and the message is dropped-with-ack by the controller.
  @spec resolve_sender_phone(map()) :: String.t() | nil
  defp resolve_sender_phone(params) do
    case params["user"]["phone"] do
      phone when phone in [nil, ""] -> recovered_sender_phone(params)
      phone -> phone
    end
  end

  @spec recovered_sender_phone(map()) :: String.t() | nil
  defp recovered_sender_phone(params) do
    phone = phone_from_message_id(params["message"])

    if own_number?(phone, params), do: nil, else: phone
  end

  # Maytapi has been observed putting the receiving managed phone in the
  # participant slot of the message id when it cannot resolve a LID sender. An
  # inbound message never originates from our own number, so treat that as
  # unresolved rather than attributing a group member's message to the
  # organization itself.
  @spec own_number?(String.t() | nil, map()) :: boolean()
  defp own_number?(nil, _params), do: false
  defp own_number?(_phone, %{"message" => %{"fromMe" => true}}), do: false
  defp own_number?(phone, params), do: phone == params["receiver"]

  @spec phone_from_message_id(map()) :: String.t() | nil
  defp phone_from_message_id(payload) do
    (payload["_serialized"] || payload["id"] || "")
    |> String.split("_")
    |> List.last()
    |> c_us_phone()
  end

  @spec c_us_phone(String.t() | nil) :: String.t() | nil
  defp c_us_phone(segment) when is_binary(segment) do
    if String.ends_with?(segment, "@c.us"),
      do: String.trim_trailing(segment, "@c.us"),
      else: nil
  end

  defp c_us_phone(_segment), do: nil

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
        phone: resolve_sender_phone(params),
        name: params["user"]["name"]
      },
      flow: flow,
      status: status
    }
  end
end
