defmodule Glific.Flows.Broadcast do
  @moduledoc """
  Start a flow to a group so we can blast it out as soon as
  possible and ensure we are under the rate limits.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Glific.{
    Contacts.Contact,
    Flows,
    Flows.Flow,
    Flows.MessageBroadcast,
    Flows.MessageBroadcastContact,
    Flows.FlowContext,
    Groups.Group,
    Messages,
    Partners,
    Repo
  }

  @status "published"

  @doc """
  The one simple public interface to broadcast a group
  """
  @spec broadcast_group(Flow.t(), Group.t()) :: map()
  def broadcast_group(flow, group) do
    # lets set up the state and then call our helper friend to split group into smaller chunks
    # of contacts
    {:ok, flow} = Flows.get_cached_flow(group.organization_id, {:flow_id, flow.id, @status})

    {:ok, group_message} =
      Messages.create_group_message(%{
        body: "Starting flow: #{flow.name} for group: #{group.label}",
        type: :text,
        group_id: group.id
      })

    {:ok, message_broadcast} = init_broadcast_group(flow, group, group_message)

    ## let's update the group message with the flow broadcast id to get the stats and everything from that later.
    {:ok, _} =
      Messages.update_message(group_message, %{message_broadcast_id: message_broadcast.id})

    ## should we broadcast the first batch here ? It can bring some inconsistency with the cron.
    flow
  end

  @doc """
  The one simple public interface to execute a group broadcast for an organization
  """
  @spec execute_group_broadcasts(any) :: :ok
  def execute_group_broadcasts(org_id) do
    # mark all the broadcast as completed if there is no unprocessed contact.
    mark_message_broadcast_completed(org_id)

    unprocessed_group_broadcast(org_id)
    |> process_broadcast_group()
  end

  @doc """
  Start a  group broadcast for a giving broadcast struct
  """
  @spec process_broadcast_group(MessageBroadcast.t() | nil) :: :ok
  def process_broadcast_group(nil), do: :ok

  def process_broadcast_group(message_broadcast) do
    Repo.put_process_state(message_broadcast.organization_id)
    opts = [message_broadcast_id: message_broadcast.id] ++ opts(message_broadcast.organization_id)
    contacts = unprocessed_contacts(message_broadcast)

    {:ok, flow} =
      Flows.get_cached_flow(
        message_broadcast.organization_id,
        {:flow_id, message_broadcast.flow_id, @status}
      )

    broadcast_contacts(flow, contacts, opts)

    :ok
  end

  @doc """
  Mark all the processed  flow broadcast as completed
  """
  @spec mark_message_broadcast_completed(non_neg_integer()) :: :ok
  def mark_message_broadcast_completed(org_id) do
    from(fb in MessageBroadcast,
      as: :message_broadcast,
      where: fb.organization_id == ^org_id,
      where: is_nil(fb.completed_at),
      where:
        not exists(
          from(
            fbc in MessageBroadcastContact,
            where:
              parent_as(:message_broadcast).id == fbc.message_broadcast_id and
                is_nil(fbc.processed_at),
            select: 1
          )
        )
    )
    |> Repo.update_all(set: [completed_at: DateTime.utc_now()])

    :ok
  end

  # function to build the opts values to process a list of contacts
  # or a group
  @spec opts(non_neg_integer) :: Keyword.t()
  defp opts(organization_id) do
    organization = Partners.organization(organization_id)

    bsp_limit = organization.services["bsp"].keys["bsp_limit"]
    bsp_limit = if is_nil(bsp_limit), do: 30, else: bsp_limit

    # lets do 80% of organization bsp limit to allow replies to come in and be processed
    bsp_limit = div(bsp_limit * 80, 100)

    [
      bsp_limit: bsp_limit,
      limit: 500,
      offset: 0,
      delay: 0
    ]
  end

  @spec unprocessed_group_broadcast(non_neg_integer) :: MessageBroadcast.t()
  defp unprocessed_group_broadcast(organization_id) do
    from(fb in MessageBroadcast,
      where:
        fb.organization_id == ^organization_id and
          is_nil(fb.completed_at),
      order_by: [desc: fb.inserted_at],
      limit: 1
    )
    |> Repo.one()
    |> Repo.preload([:flow])
  end

  @unprocessed_contact_limit 100

  defp unprocessed_contacts(message_broadcast) do
    broadcast_contacts_query(message_broadcast)
    |> limit(@unprocessed_contact_limit)
    |> order_by([c, _fbc], asc: c.id)
    |> Repo.all()
  end

  defp broadcast_contacts_query(message_broadcast) do
    Contact
    |> join(:inner, [c], fbc in MessageBroadcastContact,
      as: :fbc,
      on: fbc.contact_id == c.id and fbc.message_broadcast_id == ^message_broadcast.id
    )
    |> where(
      [c, _fbc],
      c.status not in [:blocked, :invalid] and is_nil(c.optout_time)
    )
    |> where([_c, fbc], is_nil(fbc.processed_at))
  end

  @doc """
  Lets start a bunch of contacts on a flow in parallel
  """
  @spec broadcast_contacts(map(), list(Contact.t()), Keyword.t()) :: :ok
  def broadcast_contacts(flow, contacts, opts \\ []) do
    opts =
      if opts == [],
        do: opts(flow.organization_id),
        else: opts

    contacts
    |> Enum.chunk_every(opts[:bsp_limit])
    |> Enum.with_index()
    |> Enum.each(fn {chunk_list, delay_offset} ->
      flow_tasks(
        flow,
        chunk_list,
        delay: opts[:delay] + delay_offset,
        message_broadcast_id: opts[:message_broadcast_id]
      )
    end)
  end

  @spec flow_tasks(Flow.t(), Contact.t(), Keyword.t()) :: :ok
  defp flow_tasks(flow, contacts, opts) do
    stream =
      Task.Supervisor.async_stream_nolink(
        Glific.Broadcast.Supervisor,
        contacts,
        fn contact ->
          Repo.put_process_state(contact.organization_id)

          Keyword.get(opts, :message_broadcast_id, nil)
          |> mark_message_broadcast_contact_processed(contact.id, "pending")

          response = FlowContext.init_context(flow, contact, @status, opts)

          if elem(response, 0) in [:ok, :wait] do
            Keyword.get(opts, :message_broadcast_id, nil)
            |> mark_message_broadcast_contact_processed(contact.id, "processed")
          else
            Logger.info("Could not start the flow for the contact.
               Contact id : #{contact.id} opts: #{inspect(opts)}
               response #{inspect(response)}")
          end

          :ok
        end,
        ordered: false,
        timeout: 5_000,
        on_timeout: :kill_task
      )

    Stream.run(stream)
  end

  @spec init_broadcast_group(map(), Group.t(), Messages.Message.t()) ::
          {:ok, MessageBroadcast.t()} | {:error, String.t()}
  defp init_broadcast_group(flow, group, group_message) do
    # lets create a broadcast entry for this flow
    {:ok, message_broadcast} =
      create_message_broadcast(%{
        flow_id: flow.id,
        group_id: group.id,
        message_id: group_message.id,
        started_at: DateTime.utc_now(),
        user_id: Repo.get_current_user().id,
        organization_id: group.organization_id
      })

    populate_message_broadcast_contacts(message_broadcast)
    |> case do
      {:ok, _} -> {:ok, message_broadcast}
      _ -> {:error, "could not initiate broadcast"}
    end
  end

  @spec mark_message_broadcast_contact_processed(integer() | nil, integer(), String.t()) :: :ok
  defp mark_message_broadcast_contact_processed(nil, _, _status), do: :ok

  defp mark_message_broadcast_contact_processed(message_broadcast_id, contact_id, status) do
    MessageBroadcastContact
    |> where(message_broadcast_id: ^message_broadcast_id, contact_id: ^contact_id)
    |> Repo.update_all(set: [processed_at: DateTime.utc_now(), status: status])
  end

  @spec create_message_broadcast(map()) ::
          {:ok, MessageBroadcast.t()} | {:error, Ecto.Changeset.t()}
  defp create_message_broadcast(attrs) do
    %MessageBroadcast{}
    |> MessageBroadcast.changeset(attrs)
    |> Repo.insert()
  end

  @spec populate_message_broadcast_contacts(MessageBroadcast.t()) ::
          {:ok, any()} | {:error, any()}
  defp populate_message_broadcast_contacts(message_broadcast) do
    """
    INSERT INTO message_broadcast_contacts
    (message_broadcast_id, status, organization_id, inserted_at, updated_at, contact_id)

    (SELECT #{message_broadcast.id}, 'pending', #{message_broadcast.organization_id}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, contact_id
      FROM contacts_groups left join contacts on contacts.id = contacts_groups.contact_id
      WHERE group_id = #{message_broadcast.group_id} AND (status !=  'blocked') AND (contacts.optout_time is null))
    """
    |> Repo.query()
  end

  @spec broadcast_stats_base_query(non_neg_integer()) :: String.t()
  defp broadcast_stats_base_query(message_broadcast_id) do
    """
    SELECT distinct on (message_broadcast_contacts.contact_id)
    messages.id as message_id,
    messages.status,
    message_broadcast_contacts.processed_at,
    message_broadcast_contacts.status as message_broadcast_status,
    messages.bsp_status,
    messages.errors
    FROM message_broadcast_contacts
    left JOIN messages ON messages.message_broadcast_id = message_broadcast_contacts.message_broadcast_id
    AND messages.contact_id = message_broadcast_contacts.contact_id
    WHERE message_broadcast_contacts.message_broadcast_id = #{message_broadcast_id};
    """
  end

  @doc """
  Get broadcast stats for a flow
  """
  @spec broadcast_stats(non_neg_integer()) :: {:ok, map()}
  def broadcast_stats(message_broadcast_id) do
    results =
      %{
        success: 0,
        failed: 0,
        pending: 0,
        msg_categories: %{
          sent: 0,
          read: 0,
          delivered: 0,
          enqueued: 0,
          opted_out: 0,
          error: 0
        }
      }
      |> count_successful_deliveries(message_broadcast_id)
      |> count_failed_deliveries(message_broadcast_id)
      |> count_pending_deliveries(message_broadcast_id)
      |> count_deliveries_by_category(message_broadcast_id)

    {:ok, results}
  end

  @spec count_successful_deliveries(map(), non_neg_integer()) :: map()
  defp count_successful_deliveries(map, message_broadcast_id) do
    count =
      MessageBroadcastContact
      |> where([fbc], fbc.message_broadcast_id == ^message_broadcast_id)
      |> where([fbc], not is_nil(fbc.processed_at))
      |> where([fbc], fbc.status == "processed")
      |> Repo.aggregate(:count)

    Map.put_new(map, :success, count)
  end

  @spec count_failed_deliveries(map(), non_neg_integer()) :: map()
  defp count_failed_deliveries(map, message_broadcast_id) do
    count =
      MessageBroadcastContact
      |> where([fbc], fbc.message_broadcast_id == ^message_broadcast_id)
      |> where([fbc], not is_nil(fbc.processed_at))
      |> where([fbc], fbc.status == "pending")
      |> Repo.aggregate(:count)

    Map.put_new(map, :failed, count)
  end

  @spec count_pending_deliveries(map(), non_neg_integer()) :: map()
  defp count_pending_deliveries(map, message_broadcast_id) do
    count =
      MessageBroadcastContact
      |> where([fbc], fbc.message_broadcast_id == ^message_broadcast_id)
      |> where([fbc], is_nil(fbc.processed_at))
      |> Repo.aggregate(:count)

    Map.put_new(map, :failed, count)
  end

  @spec count_deliveries_by_category(map(), non_neg_integer()) :: map()
  defp count_deliveries_by_category(map, message_broadcast_id) do
    Map.put(map, :msg_categories, msg_deliveries_by_category(message_broadcast_id))
  end

  @spec msg_deliveries_by_category(non_neg_integer()) :: map()
  defp msg_deliveries_by_category(message_broadcast_id) do
    data =
      broadcast_stats_base_query(message_broadcast_id)
      |> Repo.query!()

    sent_count =
      Enum.count(data.rows, fn d ->
        [_message_id, message_status, _processed_at, _broadcast_status, _bsp_status, _errors] = d
        message_status == "sent"
      end)

    read_count =
      Enum.count(data.rows, fn d ->
        [_message_id, _message_status, _processed_at, _broadcast_status, bsp_status, _errors] = d
        bsp_status == "read"
      end)

    delivered_count =
      Enum.count(data.rows, fn d ->
        [_message_id, _message_status, _processed_at, _broadcast_status, bsp_status, _errors] = d
        bsp_status == "delivered"
      end)

    enqueued_count =
      Enum.count(data.rows, fn d ->
        [_message_id, _message_status, _processed_at, _broadcast_status, bsp_status, _errors] = d
        bsp_status == "enqueued"
      end)

    error_count =
      Enum.count(data.rows, fn d ->
        [_message_id, _message_status, _processed_at, _broadcast_status, bsp_status, _errors] = d
        bsp_status == "error"
      end)

    %{
      sent: sent_count,
      read: read_count,
      delivered: delivered_count,
      enqueued: enqueued_count,
      error: error_count
    }
  end
end
