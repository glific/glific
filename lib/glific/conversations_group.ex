defmodule Glific.ConversationsGroup do
  @moduledoc """
  The main Glific abstraction that exposes the group conversation data in a stuctured manner as a set
  of conversations. For now each group is associated with a set of outgoing messages
  We will keep the API simple for now, but it is likely to become similar to the contact conversations
  API
  """

  use Ecto.Schema

  import Ecto.Query, warn: false

  alias Glific.{
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
    Message
    |> where([m], m.group_id in ^ids)
    |> where([m], m.message_number >= ^offset)
    |> where([m], m.message_number < ^(limit + offset))
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
    ) |> IO.inspect()
  end
end
