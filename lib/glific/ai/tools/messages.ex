defmodule Glific.AI.Tools.Messages do
  @moduledoc """
  Reads about broadcasts — messages sent to a whole collection at once.

  A broadcast that never started is a different problem from one whose messages
  failed, and only the first is visible here. One contact's conversation is read
  through `get_contact` instead, since it is almost always asked about a person.
  """

  import Ecto.Query

  alias Glific.{Flows.MessageBroadcast, Flows.MessageBroadcastContact, Repo}

  @behaviour Glific.AI.Tool

  @impl Glific.AI.Tool
  def specs do
    [
      %{
        name: "list_broadcasts",
        description: """
        Lists the broadcasts this organisation has sent, with the flow and
        collection each targeted and whether it started and completed. A
        broadcast with no completed_at is one that stalled.

        Add `include: ["contacts"]` for who it actually reached, which is how
        "some people did not get it" is answered.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"],
          include: [
            type: {:list, {:in, ["contacts"]}},
            default: [],
            doc: ~s(Add "contacts" for who each broadcast reached and who it failed for)
          ]
        ]
      }
    ]
  end

  @impl Glific.AI.Tool

  def run("list_broadcasts", args) do
    broadcasts =
      MessageBroadcast
      |> order_by([b], desc: b.inserted_at)
      |> limit(^min(args[:limit], 100))
      |> select([b], %{
        id: b.id,
        type: b.type,
        flow_id: b.flow_id,
        group_id: b.group_id,
        user_id: b.user_id,
        started_at: b.started_at,
        completed_at: b.completed_at
      })
      |> Repo.all()

    {:ok, with_contacts(broadcasts, args[:include])}
  end

  @spec with_contacts([map()], [String.t()]) :: [map()]
  defp with_contacts(broadcasts, include) do
    if "contacts" in include do
      reached = recipients(Enum.map(broadcasts, & &1.id))
      Enum.map(broadcasts, &Map.put(&1, :contacts, Map.get(reached, &1.id, [])))
    else
      broadcasts
    end
  end

  @spec recipients([non_neg_integer()]) :: map()
  defp recipients(broadcast_ids) do
    MessageBroadcastContact
    |> where([c], c.message_broadcast_id in ^broadcast_ids)
    |> limit(500)
    |> select(
      [c],
      {c.message_broadcast_id,
       %{contact_id: c.contact_id, status: c.status, processed_at: c.processed_at}}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end
end
