defmodule Glific.ConversationsGroup do
  @moduledoc """
  The main Glific abstraction that exposes the group conversation data in a structured manner as a set
  of conversations. For now each group is associated with a set of outgoing messages
  We will keep the API simple for now, but it is likely to become similar to the contact conversations
  API
  """

  use Ecto.Schema

  import Ecto.Query, warn: false

  alias Glific.{
    Conversations,
    Conversations.Conversation,
    Groups,
    Groups.Group,
    Messages.Message,
    Repo
  }

  @doc """
  Returns the last M conversations, each conversation not more than N messages
  """
  @spec list_conversations(list() | nil, map()) :: list() | integer
  def list_conversations(group_ids, args) do
    group_ids
    |> get_groups(args.contact_opts)
    |> get_conversations(args.message_opts)
  end

  @spec get_groups_query(map()) :: Ecto.Queryable.t()
  defp get_groups_query(%{limit: limit, offset: offset}) do
    Group
    |> Ecto.Queryable.to_query()
    |> Repo.add_permission(&Groups.add_permission/2)
    |> order_by([g], desc: g.last_communication_at)
    |> limit(^limit)
    |> offset(^offset)
  end

  @spec get_groups(list() | nil, map()) :: [Group.t()]
  defp get_groups(nil, opts) do
    get_groups_query(opts)
    |> Repo.all()
  end

  defp get_groups(gids, opts) when is_list(gids) do
    get_groups_query(opts)
    |> where([g], g.id in ^gids)
    |> Repo.all()
  end

  @spec get_conversations([Group.t()], map()) :: [Conversation.t()]
  defp get_conversations(groups, message_opts) do
    groups
    |> Enum.map(fn g -> g.id end)
    |> get_messages(message_opts)
    |> make_conversations(groups)
  end

  @spec get_messages(list(), map()) :: [Message.t()]
  defp get_messages(ids, %{limit: limit, offset: offset}) do
    query = from m in Message, as: :m

    query
    |> join(:inner, [m: m], c in Group, as: :c, on: c.id == m.group_id)
    |> where([m: m], m.group_id in ^ids and m.receiver_id == m.sender_id)
    |> Conversations.add_special_offset(length(ids), limit, offset)
    |> order_by([m], desc: m.inserted_at)
    |> Repo.all()
  end

  @spec make_conversations([Message.t()], [Group.t()]) :: [Conversation.t()]
  defp make_conversations(messages, groups) do
    conversations =
      groups
      |> Enum.reduce(
        %{},
        fn g, acc -> Map.put(acc, g.id, %{group: g, messages: []}) end
      )

    conversations =
      Enum.reduce(
        messages,
        conversations,
        fn m, acc ->
          Map.update!(acc, m.group_id, fn l -> %{group: l.group, messages: [m | l.messages]} end)
        end
      )
      |> Enum.map(fn {group_id, c} -> {group_id, Map.update!(c, :messages, &Enum.reverse/1)} end)
      |> Enum.into(%{})

    Enum.map(
      groups,
      fn group ->
        c = Map.get(conversations, group.id)
        Conversation.new(nil, c.group, c.messages)
      end
    )
  end

  @doc """
  Returns the last M conversations, each conversation not more than N messages
  """
  @spec wa_list_conversations(list() | nil, map()) :: list() | integer
  def wa_list_conversations(group_ids, args) do
    group_ids
    |> get_wa_groups(args.wa_group_opts)
    |> get_conversations(args.wa_message_opts)
  end

  defp get_wa_groups(gids, opts) when is_list(gids) do
    get_groups_query(opts)
    |> where([g], g.group_type == "WA")
    |> where([g], g.id in ^gids)
    |> Repo.all()
  end

  defp get_wa_groups(nil, opts) do
    get_groups_query(opts)
    |> where([g], g.group_type == "WA")
    |> Repo.all()
  end
end
