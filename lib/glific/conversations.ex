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

  @doc """
  Returns the last M conversations, each conversation not more than N messages
  """
  @spec list_conversations(map()) :: list()
  def list_conversations(args) do
    Messages.list_conversations(
      Map.put(args, :ids, get_message_ids(args.contact_opts, args.message_opts, args))
    )
  end

  @doc """
  Returns the filtered conversation by contact id
  """

  @spec conversation_by_id(map()) :: Conversation.t() | nil
  def conversation_by_id(%{contact_id: contact_id} = args) do
    args = put_in(args, [Access.key(:filter, %{}), :id], contact_id)
    message_opts = args.message_opts

    case args
         |> Map.put(:ids, get_message_ids(%{limit: 1}, message_opts, args))
         |> Messages.list_conversations() do
      [conversation] -> conversation
      _ -> nil
    end
  end

  @spec get_message_ids(map(), map(), map() | nil) :: list()
  defp get_message_ids(_contact_opts, message_opts, %{filter: %{id: id}}),
    do: get_message_ids([id], message_opts)

  defp get_message_ids(_contact_opts, message_opts, %{filter: %{ids: ids}}),
    do: get_message_ids(ids, message_opts)

  defp get_message_ids(contact_opts, message_opts, _) do
    contact_opts
    |> get_recent_contact_ids()
    |> get_message_ids(message_opts)
  end

  @spec get_message_ids(list(), map()) :: list()
  defp get_message_ids(ids, %{limit: message_limit, offset: message_offset}) do
    query =
      from m in Messages.Message,
        where:
          m.contact_id in ^ids and
            m.message_number >= ^message_offset and
            m.message_number < ^(message_limit + message_offset),
        order_by: [{:desc, :updated_at}],
        select: m.id

    Repo.all(query)
  end

  # Get the latest contact ids form messages
  @spec get_recent_contact_ids(map()) :: list()
  defp get_recent_contact_ids(contact_opts) do
    query =
      from m in Messages.Message,
        where: m.message_number == 0,
        order_by: [desc: m.updated_at],
        offset: ^contact_opts.offset,
        limit: ^contact_opts.limit,
        select: m.contact_id

    Repo.all(query)
  end
end
