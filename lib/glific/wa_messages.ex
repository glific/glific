defmodule Glific.WAMessages do
  @moduledoc """
  Whatsapp messages context
  """
  alias Glific.Conversations.WAConversation
  alias Glific.Contacts
  alias Glific.Flows.MessageVarParser
  alias Glific.Messages
  alias Glific.Repo
  alias Glific.WAGroup.WAMessage
  alias Glific.Repo
  import Ecto.Query

  @doc """
  Creates a message.
  ## Examples
      iex> create_message(%{field: value})
      {:ok, %WAMessage{}}
      iex> create_message(%{field: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_message(map()) :: {:ok, WAMessage.t()} | {:error, Ecto.Changeset.t()}
  def create_message(attrs) do
    attrs =
      %{flow: :inbound, status: :enqueued}
      |> Map.merge(attrs)
      |> parse_message_vars()
      |> put_clean_body()

    %WAMessage{}
    |> WAMessage.changeset(attrs)
    |> Repo.insert(
      returning: [:message_number, :uuid, :context_message_id],
      timeout: 45_000
    )
  end

  @doc false
  @spec update_message(WAMessage.t(), map()) ::
          {:ok, WAMessage.t()} | {:error, Ecto.Changeset.t()}
  def update_message(%WAMessage{} = message, attrs) do
    message
    |> WAMessage.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Given a list of message ids builds a conversation list with most recent conversations
  at the beginning of the list
  """
  @spec list_conversations(map(), boolean) :: [Conversation.t()] | integer
  def list_conversations(args, count \\ false) do
    args
    |> Enum.reduce(
      WAMessage,
      fn
        {:ids, ids}, query ->
          query
          |> where([m], m.id in ^ids)
          |> order_by([m], desc: m.inserted_at)

        {:filter, filter}, query ->
          query |> conversations_with(filter)

        _, query ->
          query
      end
    )
    |> do_list_conversations(args, count)
  end

  @spec parse_message_vars(map()) :: map()
  defp parse_message_vars(attrs) do
    message_vars =
      if is_integer(attrs[:contact_id]) or is_binary(attrs[:contact_id]),
        do: %{"contact" => Contacts.get_contact_field_map(attrs.contact_id)},
        else: %{}

    parse_text_message_fields(attrs, message_vars)
    |> parse_media_message_fields(message_vars)
  end

  @spec parse_text_message_fields(map(), map()) :: map()
  defp parse_text_message_fields(attrs, message_vars) do
    if is_binary(attrs[:body]) do
      {:ok, msg_uuid} = Ecto.UUID.cast(:crypto.hash(:md5, attrs.body))

      attrs
      |> Map.merge(%{
        uuid: attrs[:uuid] || msg_uuid,
        body: MessageVarParser.parse(attrs.body, message_vars)
      })
    else
      attrs
    end
  end

  @spec parse_media_message_fields(map(), map()) :: map()
  defp parse_media_message_fields(attrs, message_vars) do
    ## if message media is present change the variables in caption
    if is_integer(attrs[:media_id]) or is_binary(attrs[:media_id]) do
      message_media = Messages.get_message_media!(attrs.media_id)

      message_media
      |> Messages.update_message_media(%{
        caption: MessageVarParser.parse(message_media.caption, message_vars)
      })
    end

    attrs
  end

  @spec put_clean_body(map()) :: map()
  # sometimes we get no body, so we need to ensure we set to null for text type
  # Issue #2798
  defp put_clean_body(%{body: nil, type: :text} = attrs),
    do:
      attrs
      |> Map.put(:body, "")
      |> Map.put(:clean_body, "")

  defp put_clean_body(%{body: body} = attrs),
    do: Map.put(attrs, :clean_body, Glific.string_clean(body))

  defp put_clean_body(attrs), do: attrs

  # restrict the conversations query based on the filters in the input args
  @spec conversations_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp conversations_with(query, filter) do
    Enum.reduce(filter, query, fn
      {:id, id}, query ->
        query |> where([m], m.wa_group_id == ^id)

      {:ids, ids}, query ->
        query |> where([m], m.wa_group_id in ^ids)

      _filter, query ->
        query
    end)
  end

  defp do_list_conversations(query, _args, _count) do
    query
    |> preload([:contact, :wa_group, :context_message, :media])
    |> Repo.all()
    |> make_conversations()

    # |> add_empty_conversations(args)
  end

  # given all the messages related to multiple wa_groups, group them
  # by wa_group_id into conversation objects
  @spec make_conversations([WAMessage.t()]) :: [Conversation.t()]
  defp make_conversations(messages) do
    # now format the results,
    {wa_group_messages, _processed_groups, wa_group_order} =
      Enum.reduce(
        messages,
        {%{}, %{}, []},
        fn m, {conversations, processed_groups, wa_group_order} ->
          conversations = add(m, conversations)

          # We need to do this to maintain the sort order when returning
          # the results. The first time we see a group, we add them to
          # the wa_group_order and processed map (using a map for faster lookups)
          if Map.has_key?(processed_groups, m.wa_group_id) do
            {conversations, processed_groups, wa_group_order}
          else
            {
              conversations,
              Map.put(processed_groups, m.wa_group_id, true),
              [m.wa_group | wa_group_order]
            }
          end
        end
      )

    # Since we are doing two reduces, we end up with the right order due to the way lists are
    # constructed efficiently (add to front)
    Enum.reduce(
      wa_group_order,
      [],
      fn wa_group, acc ->
        [WAConversation.new(wa_group, Enum.reverse(wa_group_messages[wa_group])) | acc]
      end
    )
  end

  defp add_empty_conversations(results, _), do: results

  @spec add(map(), map()) :: map()
  defp add(element, map) do
    Map.update(
      map,
      element.wa_group,
      [element],
      &[element | &1]
    )
  end
end
