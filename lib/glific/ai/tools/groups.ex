defmodule Glific.AI.Tools.Groups do
  @moduledoc """
  Reads about group chats: the groups this organisation manages, the phones it
  manages them through, and the polls sent into them.

  These are group conversations, not the contact collections that
  `list_collections` returns. They go out over a different provider path from
  ordinary messages, so a group that has stopped receiving is rarely explained
  by `message_history`.
  """

  alias Glific.{Groups.WAGroups, WAManagedPhones, WaPoll}

  @behaviour Glific.AI.Tool

  @impl Glific.AI.Tool
  def specs do
    [
      %{
        name: "list_group_chats",
        description: """
        Lists the group chats this organisation manages, with the managed phone
        each one belongs to and when it last saw traffic.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      },
      %{
        name: "list_managed_phones",
        description: """
        Lists the phone numbers this organisation manages group chats through,
        with their connection status. A group that has gone quiet usually has a
        managed phone that is disconnected.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      },
      %{
        name: "list_polls",
        description: "Lists the polls this organisation has created for group chats.",
        parameters: [
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      }
    ]
  end

  @impl Glific.AI.Tool
  def run("list_group_chats", args) do
    # No `order`: this context orders by a `name` column the table lacks.
    groups =
      %{filter: %{}, opts: %{limit: min(args[:limit], 100), offset: 0}}
      |> WAGroups.list_wa_groups()
      |> Enum.map(
        &%{
          id: &1.id,
          label: &1.label,
          bsp_id: &1.bsp_id,
          wa_managed_phone_id: &1.wa_managed_phone_id,
          last_communication_at: &1.last_communication_at
        }
      )

    {:ok, groups}
  end

  def run("list_managed_phones", args) do
    phones =
      %{filter: %{}, opts: %{limit: min(args[:limit], 100), offset: 0, order: :asc}}
      |> WAManagedPhones.list_wa_managed_phones()
      |> Enum.map(
        &%{
          id: &1.id,
          label: &1.label,
          phone: &1.phone,
          status: &1.status,
          last_status_checked_at: &1.last_status_checked_at
        }
      )

    {:ok, phones}
  end

  def run("list_polls", args) do
    polls =
      %{filter: %{}, opts: %{limit: min(args[:limit], 100), offset: 0, order: :desc}}
      |> WaPoll.list_wa_polls()
      |> Enum.map(&%{id: &1.id, label: &1.label, poll_content: &1.poll_content})

    {:ok, polls}
  end
end
