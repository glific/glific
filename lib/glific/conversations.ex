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
    SELECT conversation_message_ids(ids => $1, contact_limit => $2, contact_offset => $3, message_limit => $4, message_offset => $5)
  """

  @doc """
  Returns the last M conversations, each conversation not more than N messages
  """
  @spec list_conversations(map()) :: list()
  def list_conversations(%{number_of_conversations: nc, size_of_conversations: sc} = args) do
    Messages.list_conversations(Map.put(args, :ids, get_message_ids(nc, sc, args)))
  end

  @doc """
  Returns the filtered conversation by contact id
  """
  @spec conversation_by_id(map()) :: Conversation.t()
  def conversation_by_id(%{contact_id: contact_id, size_of_conversations: sc} = args) do
    args = put_in(args, [Access.key(:filter, %{}), :id], contact_id)

    case args
         |> Map.put(:ids, get_message_ids(1, sc, args))
         |> Messages.list_conversations() do
      [conversation] -> conversation
      _ -> nil
    end
  end

  @spec get_message_ids(integer(), integer(), map() | nil) :: list()
  defp get_message_ids(nc, sc, %{filter: %{id: id}}), do: get_message_ids([[id], nc, 0, sc, 0])

  defp get_message_ids(nc, sc, %{filter: %{ids: ids}}), do: get_message_ids([ids, nc, 0, sc, 0])

  defp get_message_ids(nc, sc, _), do: get_message_ids([[], nc, 0, sc, 0])

  defp get_message_ids(opts) do
    {:ok, results} = Repo.query(@sql_ids, opts)
    List.flatten(results.rows)
  end
end
