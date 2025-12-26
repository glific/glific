defmodule Glific.Flows.Broadcast do
  @moduledoc """
  Start a flow to a group so we can blast it out as soon as
  possible and ensure we are under the rate limits.
  """

  use Publicist

  import Ecto.Query, warn: false

  require Logger

  alias Glific.{
    Contacts.Contact,
    Flows,
    Flows.Flow,
    Flows.FlowContext,
    Flows.MessageBroadcast,
    Flows.MessageBroadcastContact,
    Groups.Group,
    Groups.WaGroupsCollections,
    Messages,
    Messages.Message,
    Partners,
    Providers.Maytapi,
    Repo,
    WAGroup.WAMessage
  }

  @status "published"
  @contact_chunk 1000
  @default_bsp_limit 30
  @doc """
  The one simple public interface to broadcast a group
  """
  @spec broadcast_flow_to_group(Flow.t(), list(), map(), Keyword.t()) ::
          {:ok, MessageBroadcast.t()} | {:error, String.t()}
  def broadcast_flow_to_group(flow, group_ids, default_results \\ %{}, opts \\ [])

  def broadcast_flow_to_group(_flow, [], _default_results, _opts) do
    {:error, "Group ID is empty"}
  end

  def broadcast_flow_to_group(flow, group_ids, default_results, opts) do
    # lets set up the state and then call our helper friend to split group into smaller chunks
    # of contacts
    exclusion = Keyword.get(opts, :exclusions, false)

    group_messages =
      Enum.reduce(group_ids, [], fn group_id, acc ->
        case Repo.fetch_by(Group, %{id: group_id}) do
          {:ok, group} ->
            [create_broadcast_message(flow, group) | acc]

          {:error, _reason} ->
            acc
        end
      end)

    if Enum.empty?(group_messages) do
      {:error, "No valid groups found"}
    else
      {:ok, group_message} = hd(group_messages)
      broadcast_message_payload(group_ids, group_message, flow, default_results, exclusion)
    end
  end

  @spec create_broadcast_message(Flow.t(), Group.t()) ::
          {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  defp create_broadcast_message(flow, group) do
    Messages.create_group_message(%{
      body: "Starting flow: #{flow.name} for group: #{group.label}",
      type: :text,
      group_id: group.id
    })
  end

  @spec broadcast_message_payload(list(integer()), Message.t(), Flow.t(), map(), boolean()) ::
          {:ok, any()} | {:error, String.t()}
  defp broadcast_message_payload(group_ids, group_message, flow, default_results, exclusion) do
    %{
      group_id: hd(group_ids),
      message_id: group_message.id,
      started_at: DateTime.utc_now(),
      user_id: Repo.get_current_user().id,
      organization_id: group_message.organization_id,
      flow_id: flow.id,
      type: "flow",
      default_results: default_results
    }
    |> init_msg_broadcast(group_message, group_ids, exclusion)
  end

  @doc """
  The one simple public interface to broadcast a wa_group
  """
  @spec broadcast_flow_to_wa_group(Flow.t(), list()) :: :ok
  def broadcast_flow_to_wa_group(flow, group_ids) do
    Task.async_stream(group_ids, fn group_id ->
      Repo.put_process_state(flow.organization_id)

      wa_group_collections =
        WaGroupsCollections.list_wa_groups_collection(%{
          filter: %{group_id: group_id, organization_id: flow.organization_id}
        })
        |> Repo.preload([:wa_group])

      wa_group_collections
      |> Enum.map(& &1.wa_group_id)
      |> then(&broadcast_wa_groups(flow, &1))

      {:ok, group} = Repo.fetch_by(Group, %{id: group_id})

      {:ok, %WAMessage{}} =
        Maytapi.Message.create_wa_group_message(wa_group_collections, group, %{
          message: "Starting flow: *#{flow.name}* for group: *#{group.label}*"
        })
    end)
    |> Stream.run()
  end

  @doc """
  The one simple public interface to broadcast a group
  """
  @spec broadcast_message_to_group(Messages.Message.t(), list(), map(), map()) ::
          {:ok, MessageBroadcast.t()} | {:error, String.t()}
  def broadcast_message_to_group(group_message, group_ids, message_params, default_results \\ %{}) do
    %{
      group_id: hd(group_ids),
      message_id: group_message.id,
      started_at: DateTime.utc_now(),
      user_id: Repo.get_current_user().id,
      organization_id: group_message.organization_id,
      message_params: message_params,
      type: "message",
      default_results: default_results
    }
    |> init_msg_broadcast(group_message, group_ids, false)
  end

  @doc """
  The one simple public interface to execute a group broadcast for an organization
  """
  @spec execute_broadcasts(any) :: :ok
  def execute_broadcasts(org_id) do
    # mark all the broadcast as completed if there is no unprocessed contact.
    mark_broadcast_completed(org_id)

    unprocessed_group_broadcast(org_id)
    |> process_broadcast_group()
  end

  @doc """
  We are using this function from the flows.
  """
  @spec broadcast_wa_groups(Flow.t(), list()) :: :ok
  def broadcast_wa_groups(flow, wa_group_ids) do
    Repo.put_process_state(flow.organization_id)
    opts = opts(flow.organization_id)

    broadcast_for_wa_groups(
      %{flow: flow, type: :wa_group},
      wa_group_ids,
      opts
    )
  end

  @doc """
  We are using this function from the flows.
  """
  @spec broadcast_contacts(
          atom | %{:organization_id => non_neg_integer, optional(any) => any},
          [
            Glific.Contacts.Contact.t()
          ],
          map()
        ) :: :ok
  def broadcast_contacts(flow, contacts, default_results \\ %{}) do
    Repo.put_process_state(flow.organization_id)
    opts = opts(flow.organization_id) |> Keyword.put(:default_results, default_results)

    broadcast_for_contacts(
      %{flow: flow, type: :flow},
      contacts,
      opts
    )
  end

  @doc """
  Start a  group broadcast for a giving broadcast struct
  """
  @spec process_broadcast_group(MessageBroadcast.t() | nil) :: :ok
  def process_broadcast_group(nil), do: :ok

  def process_broadcast_group(%{type: "message"} = message_broadcast) do
    Repo.put_process_state(message_broadcast.organization_id)
    opts = [message_broadcast_id: message_broadcast.id] ++ opts(message_broadcast.organization_id)
    contacts = unprocessed_contacts(message_broadcast)
    message_params = Glific.atomize_keys(message_broadcast.message_params)

    message_params =
      Map.merge(message_params, %{
        :message_broadcast_id => message_broadcast.id,
        :organization_id => message_broadcast.organization_id,
        :group_id => message_broadcast.group_id,
        :publish? => false
      })

    broadcast_for_contacts(%{message_params: message_params, type: :message}, contacts, opts)

    :ok
  end

  def process_broadcast_group(message_broadcast) do
    Repo.put_process_state(message_broadcast.organization_id)

    opts =
      [
        message_broadcast_id: message_broadcast.id,
        default_results: message_broadcast.default_results
      ] ++ opts(message_broadcast.organization_id)

    contacts = unprocessed_contacts(message_broadcast)

    {:ok, flow} =
      Flows.get_cached_flow(
        message_broadcast.organization_id,
        {:flow_id, message_broadcast.flow_id, @status}
      )

    broadcast_for_contacts(%{flow: flow, type: :flow}, contacts, opts)

    :ok
  end

  @doc """
  Mark all the processed  flow broadcast as completed
  """
  @spec mark_broadcast_completed(non_neg_integer()) :: :ok
  def mark_broadcast_completed(org_id) do
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

  @doc """
  get_broadcast_contact_ids
  """
  @spec get_broadcast_contact_ids(MessageBroadcast.t()) :: list()
  def get_broadcast_contact_ids(message_broadcast) do
    MessageBroadcastContact
    |> where([fbc], fbc.message_broadcast_id == ^message_broadcast.id)
    |> select([fbc], fbc.contact_id)
    |> Repo.all()
  end

  # function to build the opts values to process a list of contacts
  # or a group
  @spec opts(non_neg_integer) :: Keyword.t()
  defp opts(organization_id) do
    organization = Partners.organization(organization_id)

    # nil check on organization.services["bsp"] will allow us to set Gupshup to inactive for WA groups only orgs.
    # because the value of its taken from organization.services["gupshup"] during fill_cache (lib/glific/partners.ex:608)
    # only when the credentials are active.

    bsp_limit =
      if is_nil(organization.services["bsp"]) do
        @default_bsp_limit
      else
        organization.services["bsp"].keys["bsp_limit"] || @default_bsp_limit
      end

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

  @spec broadcast_per_minute_count(non_neg_integer()) :: integer()
  defp broadcast_per_minute_count(organization_id) do
    default_limit = 100

    count_result =
      if FunWithFlags.enabled?(
           :high_trigger_tps_enabled,
           for: %{organization_id: organization_id}
         ) do
        Application.fetch_env!(:glific, :broadcast_contact_count_high_tps)
        |> Glific.parse_maybe_integer()
      else
        Application.fetch_env!(:glific, :broadcast_contact_count)
        |> Glific.parse_maybe_integer()
      end

    case count_result do
      {:ok, nil} -> default_limit
      {:ok, count} -> count
      _ -> default_limit
    end
  end

  defp unprocessed_contacts(message_broadcast) do
    contact_limit = broadcast_per_minute_count(message_broadcast.organization_id)

    broadcast_contacts_query(message_broadcast)
    |> limit(^contact_limit)
    |> order_by([c, _fbc], asc: c.id)
    |> Repo.all()
  end

  defp broadcast_contacts_query(message_broadcast) do
    Contact
    |> join(:inner, [c], fbc in MessageBroadcastContact,
      as: :fbc,
      on: fbc.contact_id == c.id and fbc.message_broadcast_id == ^message_broadcast.id
    )
    |> where([_c, fbc], is_nil(fbc.processed_at))
  end

  # """
  # Lets start a flow for a bunch of wa_groups in parallel
  # """
  @spec broadcast_for_wa_groups(map(), list(non_neg_integer()), Keyword.t()) :: :ok
  defp broadcast_for_wa_groups(attrs, wa_group_ids, opts) do
    wa_group_ids
    |> Enum.chunk_every(opts[:bsp_limit])
    |> Enum.with_index()
    |> Enum.each(fn {chunk_list, delay_offset} ->
      task_opts = [
        {:delay, opts[:delay] + delay_offset},
        {:message_broadcast_id, opts[:message_broadcast_id]},
        {:default_results, opts[:default_results]}
      ]

      wa_group_tasks(attrs.flow, chunk_list, task_opts)
    end)

    :ok
  end

  # """
  # Lets start a bunch of contacts on a flow in parallel
  # """
  @spec broadcast_for_contacts(map(), list(Contact.t()), Keyword.t()) :: :ok
  defp broadcast_for_contacts(attrs, contacts, opts) do
    contacts
    |> Enum.chunk_every(opts[:bsp_limit])
    |> Enum.with_index()
    |> Enum.each(fn {chunk_list, delay_offset} ->
      task_opts = [
        {:delay, opts[:delay] + delay_offset},
        {:message_broadcast_id, opts[:message_broadcast_id]},
        {:default_results, opts[:default_results]}
      ]

      if attrs.type == :flow,
        do: flow_tasks(attrs.flow, chunk_list, task_opts),
        else: message_tasks(attrs.message_params, chunk_list, task_opts)
    end)

    :ok
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
        timeout: 11_000,
        on_timeout: :kill_task
      )

    Stream.run(stream)
  end

  @spec wa_group_tasks(Flow.t(), [non_neg_integer()], Keyword.t()) :: :ok
  defp wa_group_tasks(flow, wa_group_ids, opts) do
    stream =
      Task.Supervisor.async_stream_nolink(
        Glific.Broadcast.Supervisor,
        wa_group_ids,
        fn wa_group_id ->
          Repo.put_process_state(flow.organization_id)
          FlowContext.init_wa_group_context(flow, wa_group_id, @status, opts)
          :ok
        end,
        ordered: false,
        timeout: 5_000,
        on_timeout: :kill_task
      )

    Stream.run(stream)
  end

  @spec message_tasks(map(), Contact.t(), Keyword.t()) :: :ok
  defp message_tasks(message_params, contacts, opts) do
    stream =
      Task.Supervisor.async_stream_nolink(
        Glific.Broadcast.Supervisor,
        contacts,
        fn contact ->
          Repo.put_process_state(contact.organization_id)

          Keyword.get(opts, :message_broadcast_id, nil)
          |> mark_message_broadcast_contact_processed(contact.id, "pending")

          message_params = Map.put(message_params, :receiver_id, contact.id)

          result =
            if message_params[:is_hsm] in [nil, false],
              do: Messages.create_and_send_message(message_params),
              else: Messages.create_and_send_hsm_message(message_params)

          case result do
            {:ok, _message} ->
              Keyword.get(opts, :message_broadcast_id, nil)
              |> mark_message_broadcast_contact_processed(contact.id, "processed")

            {:error, error} ->
              Logger.info("Could not start the message for the contact.
              Contact id : #{contact.id} opts: #{inspect(opts)}
              error #{inspect(error)}")
          end

          :ok
        end,
        ordered: false,
        timeout: 5_000,
        on_timeout: :kill_task
      )

    Stream.run(stream)
  end

  @spec init_msg_broadcast(map(), Messages.Message.t(), list(), boolean()) ::
          {:ok, MessageBroadcast.t()} | {:error, String.t()}
  defp init_msg_broadcast(broadcast_attrs, group_message, group_ids, exclusion) do
    {:ok, message_broadcast} =
      broadcast_attrs
      |> create_message_broadcast(group_ids)

    {:ok, _} =
      group_message
      |> Messages.update_message(%{message_broadcast_id: message_broadcast.id})

    populate_message_broadcast_contacts(message_broadcast, group_ids, exclusion)
  end

  @spec mark_message_broadcast_contact_processed(integer() | nil, integer(), String.t()) :: :ok
  defp mark_message_broadcast_contact_processed(nil, _, _status), do: :ok

  defp mark_message_broadcast_contact_processed(message_broadcast_id, contact_id, status) do
    MessageBroadcastContact
    |> where(message_broadcast_id: ^message_broadcast_id, contact_id: ^contact_id)
    |> Repo.update_all(set: [processed_at: DateTime.utc_now(), status: status])
  end

  @spec create_message_broadcast(map(), list()) ::
          {:ok, MessageBroadcast.t()} | {:error, Ecto.Changeset.t()}
  defp create_message_broadcast(attrs, group_ids) do
    %MessageBroadcast{}
    |> MessageBroadcast.changeset(attrs)
    |> Ecto.Changeset.put_change(:group_ids, group_ids)
    |> Repo.insert()
  end

  @spec populate_message_broadcast_contacts(MessageBroadcast.t(), list(), boolean()) ::
          {:ok, any()} | {:error, any()}
  defp populate_message_broadcast_contacts(message_broadcast, group_ids, true) do
    contact_ids =
      from(cg in Glific.Groups.ContactGroup,
        select: cg.contact_id,
        where: cg.group_id in ^group_ids
      )
      |> distinct(true)
      |> Repo.all()

    contacts_not_in_flow =
      Flow.exclude_contacts_in_flow(contact_ids)

    run_message_broadcast_contacts_query(message_broadcast, group_ids, contacts_not_in_flow)
  end

  defp populate_message_broadcast_contacts(message_broadcast, group_ids, _exclusion) do
    contact_ids =
      from(cg in Glific.Groups.ContactGroup,
        select: cg.contact_id,
        where: cg.group_id in ^group_ids
      )
      |> distinct(true)
      |> Repo.all()

    run_message_broadcast_contacts_query(message_broadcast, group_ids, contact_ids)
  end

  @spec run_message_broadcast_contacts_query(MessageBroadcast.t(), list(), list(integer())) ::
          {:ok, any()}
  defp run_message_broadcast_contacts_query(message_broadcast, group_ids, contact_ids) do
    # Batch inserting so that we can insert for large collections (15K+ for ex)
    contact_ids
    |> Enum.chunk_every(@contact_chunk)
    |> Enum.each(fn contacts_chunk ->
      contacts_chunk_str = "(" <> Enum.join(contacts_chunk, ", ") <> ")"

      query = """
      INSERT INTO message_broadcast_contacts
      (message_broadcast_id, status, organization_id, inserted_at, updated_at, contact_id, group_ids)

      (SELECT $1, 'pending', $2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, id, $3
       FROM contacts

       WHERE (status != 'blocked') AND (optout_time is null) AND id in #{contacts_chunk_str})
      """

      values = [
        message_broadcast.id,
        message_broadcast.organization_id,
        group_ids
      ]

      {:ok, _} = Repo.query(query, values)
    end)

    {:ok, message_broadcast}
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
