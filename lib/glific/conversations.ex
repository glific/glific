defmodule Glific.Conversations do
  @moduledoc """
  The main Glific abstraction that exposes the data in a stuctured manner as a set
  of conversations. For now each contact is associated with one and only one conversation.
  We will keep the API simple for now, but it is likely to become more complex and will require a
  fair number of iterations to get right
  """

  use Ecto.Schema

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Messages.Message,
    Tags.Tag,
    Repo
  }

  @doc """
  Returns the last M conversations, each conversation not more than N messages
  """
  @spec list_conversations(integer, integer) :: any
  def list_conversations(number_conversations, size_conversations) do
    @doc """
    1. First get the last unique m contact ids not including the NGO user
    2. for each of the m contact ids, select the n messages from the table

    _query =
      from m in Message,
      select: fragment("(CASE WHEN m.sender_id = 1 THEN m.receiver_id ELSE m.sender_id END) as contact_id"),
      group_by: [contact_id],
      order_by: [m.id DESC]

    _get_last_m_n_message_ids = """
    WITH cte AS
    (SELECT *, ROW_NUMBER() OVER (PARTITION BY sender_id ORDER BY updated_at DESC) AS rn FROM messages)
    SELECT * FROM cte WHERE rn <= 3 AND sender_id IN (
      SELECT sender_id FROM cte WHERE rn = 1
      ORDER BY updated_at DESC
      LIMIT m
    )
    ORDER BY sender_id, updated_at DESC
    LIMIT m * n
    """

  end
end
