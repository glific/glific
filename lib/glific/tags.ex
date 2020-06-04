defmodule Glific.Tags do
  @moduledoc """
  The Tags Context, which encapsulates and manages tags and the related join tables.
  """

  import Ecto.Query, warn: false
  alias Glific.Repo

  alias Glific.Tags.{
    Tag,
    MessageTag
  }

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
      {:order, order}, query ->
        query |> order_by({^order, :label})

      {:filter, filter}, query ->
        query |> filter_with(filter)
    end)
    |> Repo.all()
  end

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    Enum.reduce(filter, query, fn
      {:label, label}, query ->
        from q in query, where: ilike(q.label, ^"%#{label}%")

      {:language, language}, query ->
        from q in query,
          join: l in assoc(q, :language),
          where: ilike(l.label, ^"%#{language}%")
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

  @doc ~S"""
  Commenting out for now till we integrate search via GraphQL across all data types

  Simple stub for now in our experiments to implement Search
  across a variety of data types in the system.

  @search [Tag, Language]
  # can we make the return type: maybe_improper_list(Tag.t(), Language.t())
  @spec search(String.t()) :: [...]
  def search(term) do
    pattern = "%#{term}%"
    Enum.flat_map(@search, &search_ecto(&1, pattern))
  end

  @spec search_ecto(atom(), String.t()) :: [Tag.t()] | [Language.t()] | nil
  defp search_ecto(ecto_schema, pattern) do
    Repo.all(
      from q in ecto_schema,
        where: ilike(q.label, ^pattern) or ilike(q.description, ^pattern)
    )
  end
  """
  @spec no_warnings :: nil
  def no_warnings, do: nil





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
    |> Repo.preload([:recipient, :sender, :media])
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
    %MessageTag{}
    |> MessageTag.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a message tag.

  ## Examples

      iex> update_message_tag(message_tag, %{field: new_value})
      {:ok, %MessageTag{}}

      iex> update_message_tag(message_tag, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_message_tag(MessageTag.t(), map()) :: {:ok, MessageTag.t()} | {:error, Ecto.Changeset.t()}
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

      iex> change_message(message_tag)
      %Ecto.Changeset{data: %MessageTag{}}

  """
  @spec change_message(MessageTag.t(), map()) :: Ecto.Changeset.t()
  def change_message(%MessageTag{} = message_tag, attrs \\ %{}) do
    MessageTag.changeset(message_tag, attrs)
  end


end
