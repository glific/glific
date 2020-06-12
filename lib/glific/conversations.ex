defmodule Glific.Conversations do
  @moduledoc """
  The main Glific abstraction that exposes the data in a stuctured manner as a set
  of conversations. For now each contact is associated with one and only one conversation.
  We will keep the API simple for now, but it is likely to become more complex and will require a
  fair number of iterations to get right
  """

  use Ecto.Schema

  import Ecto.Query, warn: false

  alias Glific.{Messages, Repo}

  @sql_all """
  WITH cte AS
  (SELECT *, ROW_NUMBER() OVER (PARTITION BY contact_id ORDER BY updated_at DESC) AS rn FROM messages)
  SELECT id FROM cte WHERE rn <= $2 AND contact_id IN (
  SELECT contact_id FROM cte WHERE rn = 1
  ORDER BY updated_at DESC
  LIMIT $1
  )
  ORDER BY contact_id, updated_at DESC
  LIMIT $1 * $2
  """

  @sql_ids """
  WITH cte AS
  (SELECT *, ROW_NUMBER() OVER (PARTITION BY contact_id ORDER BY updated_at DESC) AS rn FROM messages)
  SELECT id FROM cte WHERE rn <= $2 AND contact_id = ANY($3)
  ORDER BY contact_id, updated_at DESC
  LIMIT $1 * $2
  """

  @doc """
  Returns the last M conversations, each conversation not more than N messages
  """
  @spec list_conversations(map()) :: any
  def list_conversations(%{number_of_conversations: nc, size_of_conversations: sc} = args) do
    {:ok, result} = get_message_ids(nc, sc, args)

    Messages.list_conversations(Map.put(args, :ids, List.flatten(result.rows)))
  end

  defp get_message_ids(nc, sc, %{filter: %{id: id}}), do: Repo.query(@sql_ids, [nc, sc, [id]])
  defp get_message_ids(nc, sc, %{filter: %{ids: ids}}), do: Repo.query(@sql_ids, [nc, sc, ids])
  defp get_message_ids(nc, sc, _), do: Repo.query(@sql_all, [nc, sc])
end
