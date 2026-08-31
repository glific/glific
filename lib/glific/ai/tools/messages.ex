defmodule Glific.AI.Tools.Messages do
  @moduledoc """
  Reads the conversation with a contact: what was sent, what came back, and
  which of it failed to deliver.

  Delivery errors live on the message row, so this is where *"they say they
  never got it"* is settled. Broadcasts are here too: a broadcast that never
  started is a different problem from one whose messages failed.
  """

  import Ecto.Query

  alias Glific.{Flows.MessageBroadcast, Messages, Repo}

  @behaviour Glific.AI.Tool

  @body 300

  @impl Glific.AI.Tool
  def specs do
    [
      %{
        name: "message_history",
        description: """
        Lists the messages exchanged with one contact, newest first, with their
        direction, delivery status and any error. Use this to check whether a
        message was actually delivered, or to see what a contact replied.
        """,
        parameters: [
          contact_id: [type: :pos_integer, required: true, doc: "The contact's id"],
          limit: [
            type: :pos_integer,
            default: 25,
            doc: "How many messages to return, at most 100"
          ]
        ]
      },
      %{
        name: "list_broadcasts",
        description: """
        Lists the broadcasts this organisation has sent, with the flow and
        collection each targeted and whether it started and completed. A
        broadcast with no completed_at is one that stalled.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      }
    ]
  end

  @impl Glific.AI.Tool
  def run("message_history", %{contact_id: contact_id} = args) do
    messages =
      %{
        filter: %{contact_id: contact_id},
        opts: %{limit: min(args[:limit], 100), offset: 0, order: :desc}
      }
      |> Messages.list_messages()
      |> Enum.map(
        &%{
          id: &1.id,
          body: truncate(&1.body),
          type: &1.type,
          flow: &1.flow,
          status: &1.status,
          bsp_status: &1.bsp_status,
          errors: &1.errors,
          is_hsm: &1.is_hsm,
          sent_at: &1.sent_at,
          inserted_at: &1.inserted_at
        }
      )

    {:ok, messages}
  end

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

    {:ok, broadcasts}
  end

  @spec truncate(String.t() | nil) :: String.t() | nil
  defp truncate(nil), do: nil

  defp truncate(text) when is_binary(text) do
    if String.length(text) > @body, do: String.slice(text, 0, @body) <> "…", else: text
  end
end
