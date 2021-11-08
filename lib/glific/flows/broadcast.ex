defmodule Glific.Flows.Broadcast do
  @moduledoc """
  Start a flow to a group so we can blast it out as soon as
  possible and ensure we are under the rate limits.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Flows,
    Flows.Flow,
    Flows.FlowBroadcast,
    Flows.FlowBroadcastContact,
    Flows.FlowContext,
    Groups.ContactGroup,
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

    init_broadcast_group(flow, group, group_message)
    # TODO
    # Need to rewrite logic here
    # 1. Create an entry in the flow broadcast table
    # 2. Create entries in the flow broadcast contacts table for each contact in group
    # 3. Return.
    # The below code runs under the minute worker which processes bsp_limit * 45
    # number of messages per minute from entries in the broadcast contacts table
    # do_broadcast(
    #   flow,
    #   group,
    #   [group_message_id: group_message.id] ++ opts(group.organization_id)
    # )

    flow
  end

  def process_broadcast_group(flow_broadcast) do
    Repo.put_process_state(flow_broadcast.organization_id)
    opts = [flow_broadcast_id: flow_broadcast.id] ++ opts(flow_broadcast.organization_id)
    contacts = unprocessed_contacts(flow_broadcast)
    broadcast_contacts(flow_broadcast.flow, contacts, opts)
  end

  def mark_flow_broadcast_completed(org_id) do
    from(fb in FlowBroadcast,
      as: :flow_broadcast,
      where: fb.organization_id == ^org_id,
      where: is_nil(fb.completed_at),
      where:
        not exists(
          from(
            fbc in FlowBroadcastContact,
            where:
              parent_as(:flow_broadcast).id == fbc.flow_broadcast_id and is_nil(fbc.processed_at),
            select: 1
          )
        )
    )
    |> Repo.update_all(set: [completed_at: DateTime.utc_now()])
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

  @unprocessed_contact_limit 150

  defp unprocessed_contacts(flow_broadcast) do
    boradcast_contacts_query(flow_broadcast)
    |> limit(@unprocessed_contact_limit)
    |> order_by([c, _fbc], asc: c.id)
    |> Repo.all()
  end

  defp boradcast_contacts_query(flow_broadcast) do
    Contact
    |> join(:inner, [c], fbc in FlowBroadcastContact,
      as: :fbc,
      on: fbc.contact_id == c.id and fbc.flow_broadcast_id == ^flow_broadcast.id
    )
    |> where([c, _fbc], c.status != :blocked and is_nil(c.optout_time))
    |> where([_c, fbc], is_nil(fbc.processed_at))
  end

  # @spec contacts_query(Group.t(), Keyword.t()) :: Ecto.Query.t()
  # defp contacts_query(group, opts) do
  #   Contact
  #   |> where([c], c.status != :blocked and is_nil(c.optout_time))
  #   |> join(:inner, [c], cg in ContactGroup,
  #     as: :cg,
  #     on: cg.contact_id == c.id and cg.group_id == ^group.id
  #   )
  #   |> limit(^opts[:limit])
  #   |> offset(^opts[:offset])
  # end

  # @spec contacts(Group.t(), Keyword.t()) :: list(Contact.t())
  # defp contacts(group, opts) do
  #   contacts_query(group, opts)
  #   |> order_by([c], asc: c.id)
  #   |> Repo.all()
  # end

  # @spec contacts_remaining?(Group.t(), Keyword.t()) :: boolean()
  # defp contacts_remaining?(group, opts) do
  #   count =
  #     contacts_query(group, opts)
  #     |> Repo.aggregate(:count)

  #   if count > 0, do: true, else: false
  # end

  # @spec do_broadcast(map(), Group.t(), Keyword.t()) :: nil
  # defp do_broadcast(flow, group, opts) do
  #   if contacts_remaining?(group, opts) do
  #     Task.Supervisor.async_nolink(
  #       Glific.Broadcast.Supervisor,
  #       fn -> broadcast_task(flow, group, opts) end,
  #       shutdown: 5_000
  #     )

  #     # lets sleep for one minute to let the system recover, if we have looped
  #     if opts[:offset] > 0, do: Process.sleep(1000 * 60)

  #     # slide the window of contacts to the next set
  #     opts =
  #       opts
  #       |> Keyword.replace!(:offset, opts[:offset] + opts[:limit])
  #       |> Keyword.replace!(:delay, opts[:delay] + ceil(opts[:limit] / opts[:bsp_limit]))

  #     do_broadcast(flow, group, opts)
  #   end

  #   nil
  # end

  # @spec broadcast_task(map(), Group.t(), Keyword.t()) :: :ok
  # defp broadcast_task(flow, group, opts) do
  #   Repo.put_process_state(group.organization_id)
  #   contacts = contacts(group, opts)
  #   broadcast_contacts(flow, contacts, opts)
  # end

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
        flow_broadcast_id: opts[:flow_broadcast_id]
      )
    end)
  end

  defp flow_tasks(flow, contacts, opts) do
    stream =
      Task.Supervisor.async_stream_nolink(
        Glific.Broadcast.Supervisor,
        contacts,
        fn contact ->
          Repo.put_process_state(contact.organization_id)
          ## update the flow broadcast contact status to processing
          FlowContext.init_context(flow, contact, @status, opts)
        end,
        ordered: false,
        timeout: 5_000,
        on_timeout: :kill_task
      )

    Stream.run(stream)
  end

  @spec init_broadcast_group(map(), Group.t(), Message.t()) :: :ok
  defp init_broadcast_group(flow, group, group_message) do
    # lets create a broadcast entry for this flow
    {:ok, flow_broadcast} =
      create_flow_broadcast(%{
        flow_id: flow.id,
        group_id: group.id,
        message_id: group_message.id,
        started_at: DateTime.utc_now(),
        user_id: Repo.get_current_user().id,
        organization_id: group.organization_id
      })

    populate_flow_broadcast_contacts(flow_broadcast)
    :ok
  end

  @spec create_flow_broadcast(map()) :: {:ok, FlowBroadcast.t()} | {:error, Ecto.Changeset.t()}
  def create_flow_broadcast(attrs) do
    %FlowBroadcast{}
    |> FlowBroadcast.changeset(attrs)
    |> Repo.insert()
  end

  @spec populate_flow_broadcast_contacts(FlowBroadcast.t()) :: :ok
  def populate_flow_broadcast_contacts(flow_broadcast) do
    current_datetime =
      DateTime.utc_now()
      |> DateTime.truncate(:second)

    attrs = %{
      flow_broadcast_id: flow_broadcast.id,
      inserted_at: current_datetime,
      updated_at: current_datetime
    }

    ContactGroup
    |> where([cg], cg.group_id == ^flow_broadcast.group_id)
    |> select([cg], %{
      contact_id: cg.contact_id,
      organization_id: cg.organization_id,
      status: "pending"
    })
    |> Repo.all()
    |> Enum.map(&Map.merge(&1, attrs))
    |> Enum.chunk_every(300)
    |> Enum.map(&Repo.insert_all(FlowBroadcastContact, &1))

    :ok
  end
end
