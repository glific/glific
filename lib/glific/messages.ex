defmodule Glific.Messages do
  @moduledoc """
  The Messages context.
  """
  import Ecto.Query, warn: false

  alias Glific.Communications.Message, as: Communications

  alias Glific.{
    Contacts.Contact,
    Conversations.Conversation,
    Messages.Message,
    Repo,
    Tags.MessageTag
  }

  @doc """
  Returns the list of filtered messages.

  ## Examples

      iex> list_messages(map())
      [%Message{}, ...]

  """
  @spec list_messages(map()) :: [Message.t()]
  def list_messages(args \\ %{}) do
    args
    |> Enum.reduce(Message, fn
      {:opts, opts}, query ->
        query |> opts_with(opts)

      {:filter, filter}, query ->
        query |> filter_with(filter)
    end)
    |> Repo.all()
  end

  defp opts_with(query, opts) do
    Enum.reduce(opts, query, fn
      {:order, order}, query ->
        query |> order_by([m], {^order, fragment("lower(?)", m.body)})

      {:limit, limit}, query ->
        query |> limit(^limit)

      {:offset, offset}, query ->
        query |> offset(^offset)
    end)
  end

  @doc """
  Return the count of messages, using the same filter as list_messages
  """
  @spec count_messages(map()) :: integer
  def count_messages(args \\ %{}) do
    args
    |> Enum.reduce(Message, fn
      {:filter, filter}, query ->
        query |> filter_with(filter)
    end)
    |> Repo.aggregate(:count)
  end

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    Enum.reduce(filter, query, fn
      {:body, body}, query ->
        from q in query, where: ilike(q.body, ^"%#{body}%")

      {:sender, sender}, query ->
        from q in query,
          join: c in assoc(q, :sender),
          where: ilike(c.name, ^"%#{sender}%")

      {:receiver, receiver}, query ->
        from q in query,
          join: c in assoc(q, :receiver),
          where: ilike(c.name, ^"%#{receiver}%")

      {:contact, contact}, query ->
        from q in query,
          join: c in assoc(q, :contact),
          where: ilike(c.name, ^"%#{contact}%")

      {:either, phone}, query ->
        from q in query,
          join: c in assoc(q, :contact),
          where: ilike(c.phone, ^"%#{phone}%")

      {:tags_included, tags_included}, query ->
        message_ids =
          MessageTag
          |> where([p], p.tag_id in ^tags_included)
          |> select([p], p.message_id)
          |> Repo.all()

        query |> where([m], m.id in ^message_ids)

      {:tags_excluded, tags_excluded}, query ->
        message_ids =
          MessageTag
          |> where([p], p.tag_id in ^tags_excluded)
          |> select([p], p.message_id)
          |> Repo.all()

        query |> where([m], m.id not in ^message_ids)

      {:provider_status, provider_status}, query ->
        from q in query, where: q.provider_status == ^provider_status
    end)
  end

  @doc """
  Gets a single message.

  Raises `Ecto.NoResultsError` if the Message does not exist.

  ## Examples

      iex> get_message!(123)
      %Message{}

      iex> get_message!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_message!(integer) :: Message.t()
  def get_message!(id), do: Repo.get!(Message, id)

  @doc """
  Creates a message.

  ## Examples

      iex> create_message(%{field: value})
      {:ok, %Message{}}

      iex> create_message(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_message(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def create_message(attrs) do
    attrs =
      %{flow: :inbound, provider_status: :delivered}
      |> Map.merge(attrs)
      |> put_contact_id()

    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  # Still need to improve this fucnation
  defp put_contact_id(attrs) do
    case attrs.flow do
      :inbound -> Map.put(attrs, :contact_id, attrs[:sender_id])
      :outbound -> Map.put(attrs, :contact_id, attrs[:receiver_id])
      _ -> attrs
    end
  end

  @doc """
  Updates a message.

  ## Examples

      iex> update_message(message, %{field: new_value})
      {:ok, %Message{}}

      iex> update_message(message, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_message(Message.t(), map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def update_message(%Message{} = message, attrs) do
    message
    |> Message.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a message.

  ## Examples

      iex> delete_message(message)
      {:ok, %Message{}}

      iex> delete_message(message)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_message(Message.t()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def delete_message(%Message{} = message) do
    Repo.delete(message)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking message changes.

  ## Examples

      iex> change_message(message)
      %Ecto.Changeset{data: %Message{}}

  """
  @spec change_message(Message.t(), map()) :: Ecto.Changeset.t()
  def change_message(%Message{} = message, attrs \\ %{}) do
    Message.changeset(message, attrs)
  end

  @doc false
  @spec fetch_and_send_message(map()) :: {:ok, Message.t()}
  def fetch_and_send_message(attrs) do
    with {:ok, message} <- Repo.fetch(Message, attrs), do: Communications.send_message(message)
  end

  @doc false
  @spec create_and_send_message(map()) :: {:ok, Message.t()}
  def create_and_send_message(attrs) do
    with {:ok, message} <- create_message(attrs), do: Communications.send_message(message)
  end

  alias Glific.Messages.MessageMedia

  @doc """
  Returns the list of message media.

  ## Examples

      iex> list_messages_media(map())
      [%MessageMedia{}, ...]

  """
  @spec list_messages_media(map()) :: [MessageMedia.t()]
  def list_messages_media(args \\ %{}) do
    args
    |> Enum.reduce(MessageMedia, fn
      {:opts, opts}, query ->
        query |> opts_media_with(opts)
    end)
    |> Repo.all()
  end

  defp opts_media_with(query, opts) do
    Enum.reduce(opts, query, fn
      {:order, order}, query ->
        query |> order_by([m], {^order, fragment("lower(?)", m.caption)})

      {:limit, limit}, query ->
        query |> limit(^limit)

      {:offset, offset}, query ->
        query |> offset(^offset)
    end)
  end

  @doc """
  Return the count of messages, using the same filter as list_messages
  """
  @spec count_messages_media(map()) :: integer
  def count_messages_media(args \\ %{}) do
    args
    |> Enum.reduce(MessageMedia, fn
      {:filter, filter}, query ->
        query |> filter_with(filter)
    end)
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets a single message media.

  Raises `Ecto.NoResultsError` if the Message media does not exist.

  ## Examples

      iex> get_message_media!(123)
      %MessageMedia{}

      iex> get_message_media!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_message_media!(integer) :: MessageMedia.t()
  def get_message_media!(id), do: Repo.get!(MessageMedia, id)

  @doc """
  Creates a message media.

  ## Examples

      iex> create_message_media(%{field: value})
      {:ok, %MessageMedia{}}

      iex> create_message_media(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_message_media(map()) :: {:ok, MessageMedia.t()} | {:error, Ecto.Changeset.t()}
  def create_message_media(attrs \\ %{}) do
    %MessageMedia{}
    |> MessageMedia.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a message media.

  ## Examples

      iex> update_message_media(message_media, %{field: new_value})
      {:ok, %MessageMedia{}}

      iex> update_message_media(message_media, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_message_media(MessageMedia.t(), map()) ::
          {:ok, MessageMedia.t()} | {:error, Ecto.Changeset.t()}
  def update_message_media(%MessageMedia{} = message_media, attrs) do
    message_media
    |> MessageMedia.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a message media.

  ## Examples

      iex> delete_message_media(message_media)
      {:ok, %MessageMedia{}}

      iex> delete_message_media(message_media)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_message_media(MessageMedia.t()) ::
          {:ok, MessageMedia.t()} | {:error, Ecto.Changeset.t()}
  def delete_message_media(%MessageMedia{} = message_media) do
    Repo.delete(message_media)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking message media changes.

  ## Examples

      iex> change_message_media(message_media)
      %Ecto.Changeset{data: %MessageMedia{}}

  """
  @spec change_message_media(MessageMedia.t(), map()) :: Ecto.Changeset.t()
  def change_message_media(%MessageMedia{} = message_media, attrs \\ %{}) do
    MessageMedia.changeset(message_media, attrs)
  end

  @doc """
  Given a list of message ids builds a conversation list with most recent conversations
  at the beginning of the list
  """
  @spec list_conversations(map()) :: [Conversation.t()]
  def list_conversations(args) do
    args
    |> Enum.reduce(Message, fn
      {:ids, ids}, query ->
        query |> where([m], m.id in ^ids)

      {:filter, filter}, query ->
        query |> conversations_with(filter)

      _, query ->
        query
    end)
    |> order_by([m], asc: m.updated_at)
    |> Repo.all()
    |> Repo.preload([:contact, :tags])
    |> make_conversations()
    |> add_empty_conversations(args)
  end

  defp make_conversations(results) do
    # now format the results,
    Enum.reduce(
      Enum.reduce(results, %{}, fn x, acc -> add(x, acc) end),
      [],
      fn {contact, messages}, acc -> [Conversation.new(contact, messages) | acc] end
    )
  end

  defp add_empty_conversations(results, %{filter: %{id: id}}),
    do: add_empty_conversation(results, [id])

  defp add_empty_conversations(results, %{filter: %{ids: ids}}),
    do: add_empty_conversation(results, ids)

  defp add_empty_conversations(results, _), do: results

  defp add_empty_conversation(results, contact_ids) do
    Enum.reduce(
      contact_ids,
      results,
      fn id, acc -> check_and_add_conversation(acc, id) end
    )
  end

  defp check_and_add_conversation(results, contact_id) do
    if Enum.find(results, fn x -> x.contact.id == contact_id end) do
      results
    else
      case Repo.fetch(Contact, contact_id) do
        {:ok, contact} -> [Conversation.new(contact, []) | results]
        {:error, _} -> results
      end
    end
  end

  @spec conversations_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp conversations_with(query, filter) do
    Enum.reduce(filter, query, fn
      {:id, id}, query ->
        query |> where([m], m.contact_id == ^id)

      {:ids, ids}, query ->
        query |> where([m], m.contact_id in ^ids)

      {:include_tags, tag_ids}, query ->
        query
        |> join(:left, [m], mt in MessageTag, on: m.id == mt.tag_id)
        |> where([m, mt], mt.tag_id in ^tag_ids)

      {:exclude_tags, tag_ids}, query ->
        query
        |> join(:left, [m], mt in MessageTag, on: m.id == mt.tag_id)
        |> where([m, mt], mt.tag_id not in ^tag_ids)
    end)
  end

  defp add(element, map) do
    Map.update(
      map,
      element.contact,
      [element],
      &[element | &1]
    )
  end
end
