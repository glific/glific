defmodule Glific.Tags do
  @moduledoc """
  The Tags Context, which encapsulates and manages tags and the related join tables.
  """

  alias Glific.Repo
  alias Glific.Tags.{ContactTag, MessageTag, Tag}

  import Ecto.Query, warn: false

  @doc """
  Returns the list of tags.

  ## Examples

      iex> list_tags()
      [%Tag{}, ...]

  """
  @spec list_tags(map()) :: [Tag.t()]
  def list_tags(args \\ %{}) do
    args
    |> Enum.reduce(Tag, fn
      {:opts, opts}, query ->
        query |> opts_with(opts)

      {:filter, filter}, query ->
        query |> filter_with(filter)
    end)
    |> Repo.all()
  end

  @doc """
  Return the count of tags, using the same filter as list_tags
  """
  @spec count_tags(map()) :: integer
  def count_tags(args \\ %{}) do
    args
    |> Enum.reduce(Tag, fn
      {:filter, filter}, query ->
        query |> filter_with(filter)
    end)
    |> Repo.aggregate(:count)
  end

  defp opts_with(query, opts) do
    Enum.reduce(opts, query, fn
      {:order, order}, query ->
        query |> order_by([t], {^order, fragment("lower(?)", t.label)})

      {:limit, limit}, query ->
        query |> limit(^limit)

      {:offset, offset}, query ->
        query |> offset(^offset)
    end)
  end

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    Enum.reduce(filter, query, fn
      {:label, label}, query ->
        from q in query, where: ilike(q.label, ^"%#{label}%")

      {:parent, label}, query ->
        from q in query,
          join: t in assoc(q, :parent),
          where: ilike(t.label, ^"%#{label}%")

      {:parent_id, parent_id}, query ->
        from q in query,
          where: q.parent_id == ^parent_id

      {:language, language}, query ->
        from q in query,
          join: l in assoc(q, :language),
          where: ilike(l.label, ^"%#{language}%")

      {:language_id, language_id}, query ->
        from q in query,
          where: q.language_id == ^language_id
    end)
  end

  @doc """
  Gets a single tag.

  Raises `Ecto.NoResultsError` if the Tag does not exist.

  ## Examples

      iex> get_tag!(123)
      %Tag{}

      iex> get_tag!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_tag!(integer) :: Tag.t()
  def get_tag!(id), do: Repo.get!(Tag, id)

  @doc """
  Creates a tag.

  ## Examples

      iex> create_tag(%{field: value})
      {:ok, %Tag{}}

      iex> create_tag(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_tag(map()) :: {:ok, Tag.t()} | {:error, Ecto.Changeset.t()}
  def create_tag(attrs \\ %{}) do
    %Tag{}
    |> Tag.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a tag.

  ## Examples

      iex> update_tag(tag, %{field: new_value})
      {:ok, %Tag{}}

      iex> update_tag(tag, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_tag(Tag.t(), map()) :: {:ok, Tag.t()} | {:error, Ecto.Changeset.t()}
  def update_tag(%Tag{} = tag, attrs) do
    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a tag.

  ## Examples

      iex> delete_tag(tag)
      {:ok, %Tag{}}

      iex> delete_tag(tag)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_tag(Tag.t()) :: {:ok, Tag.t()} | {:error, Ecto.Changeset.t()}
  def delete_tag(%Tag{} = tag) do
    tag
    |> Tag.changeset(%{})
    |> Repo.delete()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking tag changes.

  ## Examples

      iex> change_tag(tag)
      %Ecto.Changeset{data: %Tag{}}

  """
  @spec change_tag(Tag.t(), map()) :: Ecto.Changeset.t()
  def change_tag(%Tag{} = tag, attrs \\ %{}) do
    Tag.changeset(tag, attrs)
  end

  @doc """
    Converts all tag kewords into the map where keyword is the key and tag id is the value
  """
  @spec keyword_map() :: map()
  def keyword_map do
    Tag
    |> where([t], not is_nil(t.keywords))
    |> where([t], fragment("array_length(?, 1)", t.keywords) > 0)
    |> select([:id, :keywords])
    |> Repo.all()
    |> Enum.reduce(%{}, &keyword_map(&1, &2))
  end

  @spec keyword_map(map(), map) :: map()
  defp keyword_map(%{id: tag_id, keywords: keywords}, acc) do
    keywords
    |> Enum.reduce(%{}, &Map.put(&2, &1, tag_id))
    |> Map.merge(acc)
  end

  @doc """
    Filter all the status tag and returns as a map
  """

  @spec status_map() :: map()
  def status_map do
    status_tags = ["New Contact", "Not Replied", "Unread"]

    Tag
    |> where([t], t.label in ^status_tags)
    |> select([:id, :label])
    |> Repo.all()
    |> Enum.reduce(%{}, fn tag, acc -> Map.put(acc, tag.label, tag.id) end)
  end

  @doc """
  Returns the list of messages tags.

  ## Examples

      iex> list_messages_tags()
      [%MessageTag{}, ...]

  """
  @spec list_messages_tags(map()) :: [MessageTag.t()]
  def list_messages_tags(_args \\ %{}) do
    Repo.all(MessageTag)
  end

  @doc """
  Gets a single message.

  Raises `Ecto.NoResultsError` if the Message does not exist.

  ## Examples

      iex> get_message_tag!(123)
      %Message{}

      iex> get_message_tag!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_message_tag!(integer) :: MessageTag.t()
  def get_message_tag!(id) do
    Repo.get!(MessageTag, id)
  end

  @doc """
  Creates a message.

  ## Examples

      iex> create_message_tag(%{field: value})
      {:ok, %Message{}}

      iex> create_message_tag(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_message_tag(map()) :: {:ok, MessageTag.t()} | {:error, Ecto.Changeset.t()}
  def create_message_tag(attrs \\ %{}) do
    # Merge default values if not present in attributes
    # do an upsert
    %MessageTag{}
    |> MessageTag.changeset(attrs)
    |> Repo.insert(on_conflict: :replace_all, conflict_target: [:message_id, :tag_id])
  end

  @doc """
  Updates a message tag.

  ## Examples

      iex> update_message_tag(message_tag, %{field: new_value})
      {:ok, %MessageTag{}}

      iex> update_message_tag(message_tag, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_message_tag(MessageTag.t(), map()) ::
          {:ok, MessageTag.t()} | {:error, Ecto.Changeset.t()}
  def update_message_tag(%MessageTag{} = message_tag, attrs) do
    message_tag
    |> MessageTag.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a message tag.

  ## Examples

      iex> delete_message_tag(message_tag)
      {:ok, %MessageTag{}}

      iex> delete_message_tag(message_tag)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_message_tag(MessageTag.t()) :: {:ok, MessageTag.t()} | {:error, Ecto.Changeset.t()}
  def delete_message_tag(%MessageTag{} = message_tag) do
    Repo.delete(message_tag)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking message changes.

  ## Examples

      iex> change_message_tag(message_tag)
      %Ecto.Changeset{data: %MessageTag{}}

  """
  @spec change_message_tag(MessageTag.t(), map()) :: Ecto.Changeset.t()
  def change_message_tag(%MessageTag{} = message_tag, attrs \\ %{}) do
    MessageTag.changeset(message_tag, attrs)
  end

  @doc """
  Returns the list of contacts tags.

  ## Examples

      iex> list_contacts_tags()
      [%ContactTag{}, ...]

  """
  @spec list_contacts_tags(map()) :: [ContactTag.t()]
  def list_contacts_tags(_args \\ %{}) do
    Repo.all(ContactTag)
  end

  @doc """
  Gets a single contact.

  Raises `Ecto.NoResultsError` if the Contact does not exist.

  ## Examples

      iex> get_contact_tag!(123)
      %Contact{}

      iex> get_contact_tag!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_contact_tag!(integer) :: ContactTag.t()
  def get_contact_tag!(id) do
    Repo.get!(ContactTag, id)
  end

  @doc """
  Creates a contact.

  ## Examples

      iex> create_contact_tag(%{field: value})
      {:ok, %Contact{}}

      iex> create_contact_tag(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_contact_tag(map()) :: {:ok, ContactTag.t()} | {:error, Ecto.Changeset.t()}
  def create_contact_tag(attrs \\ %{}) do
    # Merge default values if not present in attributes
    %ContactTag{}
    |> ContactTag.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a contact tag.

  ## Examples

      iex> update_contact_tag(contact_tag, %{field: new_value})
      {:ok, %ContactTag{}}

      iex> update_contact_tag(contact_tag, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_contact_tag(ContactTag.t(), map()) ::
          {:ok, ContactTag.t()} | {:error, Ecto.Changeset.t()}
  def update_contact_tag(%ContactTag{} = contact_tag, attrs) do
    contact_tag
    |> ContactTag.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a contact tag.

  ## Examples

      iex> delete_contact_tag(contact_tag)
      {:ok, %ContactTag{}}

      iex> delete_contact_tag(contact_tag)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_contact_tag(ContactTag.t()) :: {:ok, ContactTag.t()} | {:error, Ecto.Changeset.t()}
  def delete_contact_tag(%ContactTag{} = contact_tag) do
    Repo.delete(contact_tag)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking contact changes.

  ## Examples

      iex> change_contact_tag(contact_tag)
      %Ecto.Changeset{data: %ContactTag{}}

  """
  @spec change_contact_tag(ContactTag.t(), map()) :: Ecto.Changeset.t()
  def change_contact_tag(%ContactTag{} = contact_tag, attrs \\ %{}) do
    ContactTag.changeset(contact_tag, attrs)
  end
end
