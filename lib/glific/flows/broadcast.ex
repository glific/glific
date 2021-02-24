defmodule Glific.Flows.Broadcast do
  @moduledoc """
  Start a flow to a group so we can blast it out as soon as
  possible and ensure we are under the rate limits.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Flows,
    Flows.Flow,
    Flows.FlowContext,
    Groups.Group,
    Messages,
    Partners,
    Partners.Organization,
    Repo
  }

  @doc """
  The one simple public interface
  """
  @spec broadcast(Group.t(), Flow.t()) :: nil
  def broadcast(group, flow) do
    # lets set up the state and then call our helper friend smallcast
    status = "published"

    {:ok, flow} = Flows.get_cached_flow(group.organization_id, {:flow_id, flow.id, status})

    {:ok, _group_message} =
      Messages.create_group_message(%{
        body: "Starting flow: #{flow.name} for group: #{group.label}",
        type: :text,
        group_id: group.id
      })

    organization = Partners.organization(flow.organization_id)

    opts = [
      organization: organization,
      bsp_limit: bsp_limit(organization),
      limit: 0,
      offset: 1000,
      size: 1000,
      delay: 0
    ]

    do_broadcast(group, flow, opts)
  end

  @spec bsp_limit(Organization.t()) :: non_neg_integer
  defp bsp_limit(organization) do
    bsp_limit = organization.services["bsp"].keys["bsp_limit"]
    bsp_limit = if is_nil(bsp_limit), do: 30, else: bsp_limit
    # lets do 80% of organization bsp limit to allow replies to come in and be processed
    div(bsp_limit * 80, 100)
  end

  @spec contacts(Group.t(), Keyword.t()) :: Ecto.Query.t()
  defp contacts(group, opts) do
    Contact
    |> where([c], c.status != :blocked and is_nil(c.optout_time))
    |> join(:inner, [c], cg in ContactGroup,
      as: :cg,
      on: cg.contact_id == c.id and cg.group_id == ^group.id
    )
    |> limit(^opts[:limit])
    |> offset(^opts[:offset])
    |> order_by([c], asc: c.id)
    |> Repo.all()
  end

  @spec do_broadcast(Group.t(), map(), Keyword.t()) :: nil
  defp do_broadcast(group, flow, opts) do
    contacts = contacts(group, opts)

    if contacts != [] do
      contacts
      |> Enum.chunk_every(opts[:bsp_limit])
      |> Enum.with_index()
      |> Enum.each(fn {contacts, delay} ->
        broadcast_flow(contacts, flow, opts[:delay] + delay)
      end)

      do_broadcast(
        group,
        flow,
        opts
        |> Keyword.replace!(:offset, opts[:offset] + opts[:size])
        |> Keyword.replace!(:delay, opts[:delay] + ceil(opts[:size] / opts[:bsp_limit]))
      )
    end
  end

  @status "published"

  @spec broadcast_flow(list(), map(), non_neg_integer) :: nil
  defp broadcast_flow(contacts, flow, delay) do
    for contact <- contacts do
      if Contacts.can_send_message_to?(contact) do
        FlowContext.init_context(flow, contact, @status, delay: delay)
      end
    end
  end
end
