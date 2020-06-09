@defmodule Glific.Conversations do
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
    Tags.Tag
    Repo
  }

  @doc """
  Returns the last M conversations, each conversation not more than N messages
  """
  @spec list_conversations(integer, integer) :: any
  def list_conversations(number_conversations, size_conversations) do
    query =
      from m in Message,
      select: [m.sender_id, m.receiver_id]
      order_by: [desc: m.id]



end
