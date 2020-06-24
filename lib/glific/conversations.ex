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

  # Default values for the conversation. User will be able to override them in the API calls
  @default_opts %{
    message_opts: %{offset: 0, limit: 25},
    contact_opts: %{offset: 0, limit: 10}
  }

  @doc """
  Returns the last M conversations, each conversation not more than N messages
  """
  @spec list_conversations(map()) :: list()
  def list_conversations(args) do
    args = Map.merge(@default_opts, args, fn _k, v1, v2 -> v1 |> Map.merge(v2) end)
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
    message_opts = Map.merge(@default_opts.message_opts, args.message_opts)

    case args
         |> Map.put(:ids, get_message_ids(%{limit: 1}, message_opts, args))
         |> Messages.list_conversations() do
      [conversation] -> conversation
      _ -> nil
    end
  end

  @spec get_message_ids(map(), map(), map() | nil) :: list()
  defp get_message_ids(contact_opts, message_opts, %{filter: %{id: id}}),
    do: get_message_ids([[id], contact_opts.limit, 0, message_opts.limit, message_opts.offset])

  defp get_message_ids(contact_opts, message_opts, %{filter: %{ids: ids}}),
    do: get_message_ids([ids, contact_opts.limit, 0, message_opts.limit, message_opts.offset])

  defp get_message_ids(contact_opts, message_opts, _),
    do:
      get_message_ids([
        [],
        contact_opts.limit,
        contact_opts.offset,
        message_opts.limit,
        message_opts.offset
      ])

  defp get_message_ids(opts) do
    {:ok, results} = Repo.query(@sql_ids, opts)
    List.flatten(results.rows)
  end
end
