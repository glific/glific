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
    Flows.FlowBroadcast,
    Flows.FlowBroadcastContact,
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

    init_broadcast_group(flow, group, group_message)

    ## should we start the flow broadcast here ? It can bring some inconsistency with the cron.
    flow
  end

  @doc """
  The one simple public interface to exceute a group broadcast for an organization
  """
  @spec execute_group_broadcasts(any) :: :ok
  def execute_group_broadcasts(org_id) do
    # mark all the broadcast as completed if there is no unprocessed contact.
    mark_flow_broadcast_completed(org_id)

    unprocessed_group_broadcast(org_id)
    |> process_broadcast_group()
  end

  @doc """
  Start a  group broadcast for a giving broadcast stuct
  """
  @spec process_broadcast_group(FlowBroadcast.t() | nil) :: :ok
  def process_broadcast_group(nil), do: :ok

  def process_broadcast_group(flow_broadcast) do
    Repo.put_process_state(flow_broadcast.organization_id)
    opts = [flow_broadcast_id: flow_broadcast.id] ++ opts(flow_broadcast.organization_id)
    contacts = unprocessed_contacts(flow_broadcast)

    {:ok, flow} =
      Flows.get_cached_flow(
        flow_broadcast.organization_id,
        {:flow_id, flow_broadcast.flow_id, @status}
      )

    broadcast_contacts(flow, contacts, opts)

    :ok
  end

  @doc """
    mark all the proceesed  flow broadcast as completed
  """
  @spec mark_flow_broadcast_completed(non_neg_integer()) :: :ok
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

  defp unprocessed_group_broadcast(organization_id) do
    from(fb in FlowBroadcast,
      as: :flow_broadcast,
      where: fb.organization_id == ^organization_id,
      where: is_nil(fb.completed_at),
      limit: 1
    )
    |> Repo.one()
    |> Repo.preload([:flow])
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
          response = FlowContext.init_context(flow, contact, @status, opts)

          if elem(response, 0) in [:ok, :wait] do
            Keyword.get(opts, :flow_broadcast_id, nil)
            |> mark_flow_broadcast_contact_proceesed(contact.id, "processed")
          else
            Logger.info("Could not start the flow for the contact.
               Contact id : #{contact.id} opts: #{inspect(opts)}
               response #{inspect(response)}")

            Keyword.get(opts, :flow_broadcast_id, nil)
            |> mark_flow_broadcast_contact_proceesed(contact.id, "pending")
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
          {:ok, FlowContext.t()} | {:error, String.t()}
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
    |> case do
      {:ok, _} -> {:ok, flow_broadcast}
      _ -> {:error, "could not initiate broadcast"}
    end
  end

  @spec mark_flow_broadcast_contact_proceesed(integer() | nil, integer(), String.t()) :: :ok
  defp mark_flow_broadcast_contact_proceesed(nil, _, _status), do: :ok

  defp mark_flow_broadcast_contact_proceesed(flow_boradcast_id, contact_id, status) do
    FlowBroadcastContact
    |> where(flow_broadcast_id: ^flow_boradcast_id, contact_id: ^contact_id)
    |> Repo.update_all(set: [processed_at: DateTime.utc_now(), status: status])
  end

  @spec create_flow_broadcast(map()) :: {:ok, FlowBroadcast.t()} | {:error, Ecto.Changeset.t()}
  defp create_flow_broadcast(attrs) do
    %FlowBroadcast{}
    |> FlowBroadcast.changeset(attrs)
    |> Repo.insert()
  end

  @spec populate_flow_broadcast_contacts(FlowBroadcast.t()) :: {:ok, any()} | {:error, any()}
  defp populate_flow_broadcast_contacts(flow_broadcast) do
    """
    INSERT INTO flow_broadcast_contacts
    (flow_broadcast_id, status, organization_id, inserted_at, updated_at, contact_id)

    (SELECT #{flow_broadcast.id}, 'pending', #{flow_broadcast.organization_id}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, contact_id
      FROM contacts_groups left join contacts on contacts.id = contacts_groups.contact_id
      WHERE group_id = #{flow_broadcast.group_id} AND (status !=  'blocked') AND (contacts.optout_time is null))
    """
    |> Repo.query()
  end
end
