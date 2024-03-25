defmodule Glific.WAConversations do
  @moduledoc """
  The main Glific abstraction for Whatsapp groups that exposes the data in a structured manner as a set
  of conversations.
  """

  require Logger

  import Ecto.Query, warn: false

  alias Glific.{Groups.WAGroup, Repo, WAGroup.WAMessage, WAMessages}

  @doc """
  Returns the last M conversations, each conversation not more than N messages
  """
  @spec list_conversations(map()) :: list() | integer
  def list_conversations(args) do
    args
    |> Map.put(:ids, get_message_ids(args.wa_group_opts, args.wa_message_opts, args))
    |> WAMessages.list_conversations()
  rescue
    ex ->
      Logger.error("Search threw a Error: #{inspect(ex)}")
      []
  end

  defp get_message_ids(_wa_group_opts, wa_message_opts, %{filter: %{ids: ids}}),
    do: get_message_ids(ids, wa_message_opts)

  @spec get_message_ids(list(), map()) :: list()
  defp get_message_ids(ids, %{limit: message_limit, offset: message_offset}) do
    query = from m in WAMessage, as: :m

    query
    |> join(:inner, [m: m], g in WAGroup, as: :g, on: g.id == m.wa_group_id)
    |> where([m: m], m.wa_group_id in ^ids and m.is_dm == false)
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
    |> where([m: m, g: g], m.message_number <= g.last_message_number)
    |> where([m: m, g: g], m.message_number > g.last_message_number - ^limit)
  end

  def add_special_offset(query, 1, limit, offset) do
    # this is for one group, so we assume offset is message number
    # and we want messages from this message and older
    final = offset + limit

    query
    |> where([m: m, g: g], m.message_number >= ^offset)
    |> where([m: m, g: g], m.message_number <= ^final)
  end

  def add_special_offset(query, _, limit, offset) do
    # this is for multiple contacts/groups
    start = offset + limit

    query
    |> where([m: m, g: g], m.message_number >= g.last_message_number - ^start)
    |> where([m: m, g: g], m.message_number <= g.last_message_number - ^offset)
  end
end
