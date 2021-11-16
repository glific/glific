defmodule Glific.Conversations do
  @moduledoc """
  The main Glific abstraction that exposes the data in a stuctured manner as a set
  of conversations. For now each contact is associated with one and only one conversation.
  We will keep the API simple for now, but it is likely to become more complex and will require a
  fair number of iterations to get right
  """

  use Ecto.Schema

  import Ecto.Query, warn: false

  alias Glific.{Contacts.Contact, Messages, Messages.Message, Repo}

  @doc """
  Returns the last M conversations, each conversation not more than N messages
  """
  @spec list_conversations(map(), boolean) :: list() | integer
  def list_conversations(args, count \\ false) do
    args
    |> Map.put(:ids, get_message_ids(args.contact_opts, args.message_opts, args))
    |> Messages.list_conversations(count)
  end

  @spec get_message_ids(map(), map(), map() | nil) :: list()
  defp get_message_ids(_contact_opts, message_opts, %{filter: %{id: id}}),
    do: get_message_ids([id], message_opts)

  defp get_message_ids(_contact_opts, message_opts, %{filter: %{ids: ids}}),
    do: get_message_ids(ids, message_opts)

  @spec get_message_ids(list(), map()) :: list()
  defp get_message_ids(ids, %{limit: message_limit, offset: message_offset}) do
    query = from m in Message, as: :m

    query
    |> join(:inner, [m: m], c in Contact, as: :c, on: c.id == m.contact_id)
    |> where([m: m], m.contact_id in ^ids and m.receiver_id != m.sender_id)
    |> add_special_offset(length(ids), message_limit, message_offset)
    |> select([m: m], m.id)
    |> Repo.all(timeout: 10_000)
  end

  @doc """
  Adding special offset to calculate recent message based on message number
  """
  @spec add_special_offset(Ecto.Query.t(), integer, integer, integer) :: Ecto.Query.t()
  def add_special_offset(query, _, limit, 0) do
    # always cap out limit to 250, in case frontend sends too many
    limit = min(limit, 250)

    # this is for the latest messages, irrespective whether its for one or multiple contact/group
    query
    |> where([m: m, c: c], m.message_number <= c.last_message_number)
    |> where([m: m, c: c], m.message_number > c.last_message_number - ^limit)
  end

  def add_special_offset(query, 1, limit, offset) do
    # this is for one contact/group, so we assume offset is message number
    # and we want messages from this message and older
    final = offset + limit

    query
    |> where([m: m, c: c], m.message_number >= ^offset)
    |> where([m: m, c: c], m.message_number <= ^final)
  end

  def add_special_offset(query, _, limit, offset) do
    # this is for multiple contacts/groups
    start = offset + limit

    query
    |> where([m: m, c: c], m.message_number >= c.last_message_number - ^start)
    |> where([m: m, c: c], m.message_number <= c.last_message_number - ^offset)
  end
end
