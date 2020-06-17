defmodule Glific.Conversations do
  @moduledoc """
  The main Glific abstraction that exposes the data in a stuctured manner as a set
  of conversations. For now each contact is associated with one and only one conversation.
  We will keep the API simple for now, but it is likely to become more complex and will require a
  fair number of iterations to get right
  """

  use Ecto.Schema

  import Ecto.Query, warn: false

  alias Glific.{Conversations.Conversation, Messages, Repo}

  @sql_ids """
      SELECT id, ancestors FROM messages WHERE id IN ( SELECT MAX(id) FROM messages GROUP BY contact_id ) and contact_id = ANY($2) ORDER By updated_at DESC LIMIT $1;
  """

  @sql_all """
      SELECT id, ancestors FROM messages WHERE id IN ( SELECT MAX(id) FROM messages GROUP BY contact_id ) ORDER By updated_at DESC LIMIT $1;
  """

  @doc """
  Returns the last M conversations, each conversation not more than N messages
  """
  @spec list_conversations(map()) :: list()
  def list_conversations(%{number_of_conversations: nc, size_of_conversations: sc} = args),
    do: Messages.list_conversations(Map.put(args, :ids, get_message_ids(nc, sc, args)))

  @doc """
  Returns the filtered conversation by contact id
  """
  @spec conversation_by_id(map()) :: Conversation.t()
  def conversation_by_id(
        %{contact_id: contact_id, size_of_conversations: sc, filter: filter} = args
      ) do
    filter = Map.put(filter, :id, contact_id)
    args = Map.merge(args, %{filter: filter})

    conversations_list =
      Messages.list_conversations(Map.put(args, :ids, get_message_ids(1, sc, args)))

    case conversations_list do
      [conversation] ->
        conversation

      [] ->
        nil
    end
  end

  @spec get_message_ids(integer(), integer(), map() | nil) :: list()
  defp get_message_ids(nc, sc, %{filter: %{id: id}}),
    do: process_results(Repo.query(@sql_ids, [nc, [id]]), sc)

  defp get_message_ids(nc, sc, %{filter: %{ids: ids}}),
    do: process_results(Repo.query(@sql_ids, [nc, ids]), sc)

  defp get_message_ids(nc, sc, _),
    do: process_results(Repo.query(@sql_all, [nc]), sc)

  @spec process_results({:ok, map()}, integer()) :: list()
  defp process_results({:ok, results}, sc) do
    results.rows
    |> Enum.reduce([], fn [last_message_id | [ancestors]], acc ->
      acc ++ [last_message_id | Enum.take(ancestors, sc)]
    end)
  end
end
