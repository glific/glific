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

  @sql """
  WITH cte AS
  (SELECT *, ROW_NUMBER() OVER (PARTITION BY contact_id ORDER BY updated_at DESC) AS rn FROM messages)
  SELECT id FROM cte WHERE rn <= $2 AND contact_id IN (
  SELECT contact_id FROM cte WHERE rn = 1
  ORDER BY updated_at DESC
  LIMIT $1
  )
  ORDER BY sender_id, updated_at DESC
  LIMIT $1 * $2
  """

  @doc """
  Returns the last M conversations, each conversation not more than N messages
  """
  @spec list_conversations(map()) :: any
  def list_conversations(%{number_of_conversations: nc, size_of_conversations: sc} = _args) do
    # Get the last unique m contact ids not including the NGO user and for each of them fetch the last
    # m messages
    {:ok, result} = Repo.query(@sql, [nc, sc])

    Messages.get_conversations(List.flatten(result.rows))
  end
end
