defmodule Glific.Tags do
  @moduledoc """
  The Tags Context, which encapsulates and manages tags and the related join tables.
  """

  alias Glific.{
    Communications,
    Repo,
    Taggers
  }

  alias Glific.Tags.{
    ContactTag,
    MessageTag,
    Tag,
    TemplateTag
  }

  import Ecto.Query

  @doc """
  Returns the list of tags.

  ## Examples

      iex> list_tags()
      [%Tag{}, ...]

  """
  @spec list_tags(map()) :: [Tag.t()]
  def list_tags(%{filter: %{organization_id: _organization_id}} = args),
    do: Repo.list_filter(args, Tag, &Repo.opts_with_label/2, &Repo.filter_with/2)

  @doc """
  Return the count of tags, using the same filter as list_tags
  """
  @spec count_tags(map()) :: integer
  def count_tags(%{filter: %{organization_id: _organization_id}} = args),
    do: Repo.count_filter(args, Tag, &Repo.filter_with/2)

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
  def create_tag(%{organization_id: organization_id} = attrs) do
    Taggers.reset_tag_maps(organization_id)

    %Tag{}
    |> Tag.changeset(check_shortcode(attrs))
    |> Repo.insert()
  end

  # Adding this so that frontend does not fix it
  # immediately, will remove this very soon
  @spec check_shortcode(map()) :: map()
  defp check_shortcode(%{shortcode: _shortcode} = attrs),
    do: attrs

  defp check_shortcode(%{label: nil} = attrs),
    do: attrs

  defp check_shortcode(%{label: label} = attrs),
    do: Map.update(attrs, :shortcode, Glific.string_clean(label), & &1)

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
    Taggers.reset_tag_maps(tag.organization_id)

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
  @spec keyword_map(map()) :: map()
  def keyword_map(%{organization_id: organization_id}) do
    Tag
    |> where([t], not is_nil(t.keywords))
    |> where([t], fragment("array_length(?, 1)", t.keywords) > 0)
    |> where([t], t.organization_id == ^organization_id)
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
  @spec status_map(map()) :: %{String.t() => integer}
  def status_map(%{organization_id: organization_id}),
    do:
      Repo.label_id_map(
        Tag,
        ["language", "newcontact", "notreplied", "unread"],
        organization_id,
        :shortcode
      )

  @doc """
  Given a tag id or a list of tag ids, retrieve all the ancestors for the list_tags
  """
  @spec include_all_ancestors(non_neg_integer | [non_neg_integer]) :: [non_neg_integer]
  def include_all_ancestors(tag_id) when is_integer(tag_id),
    do: include_all_ancestors([tag_id])

  def include_all_ancestors(tag_ids) do
    Tag
    |> where([t], t.id in ^tag_ids)
    |> select([t], t.ancestors)
    |> Repo.all()
    |> List.flatten()
    |> Enum.concat(tag_ids)
    |> Enum.uniq()
  end

  @doc """
  Given a shortcode of tag, retrieve all the children for the tag
  """
  @spec get_all_children(String.t(), non_neg_integer) :: [Tag.t()]
  def get_all_children(shortcode, organization_id) do
    {:ok, flow_tag} =
      Glific.Repo.fetch_by(Glific.Tags.Tag, %{
        shortcode: shortcode,
        organization_id: organization_id
      })

    Glific.Tags.Tag
    |> where([t], ^flow_tag.id in t.ancestors)
    |> Glific.Repo.all()
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
  Creates a message tag

  ## Examples

  iex> create_message_tag(%{field: value})
  {:ok, %Message{}}

  iex> create_message_tag(%{field: bad_value})
  {:error, %Ecto.Changeset{}}

  """
  @spec create_message_tag(map()) :: {:ok, MessageTag.t()} | {:error, Ecto.Changeset.t()}
  def create_message_tag(attrs \\ %{}) do
    {status, response} =
      %MessageTag{}
      |> MessageTag.changeset(attrs)
      |> Repo.insert(on_conflict: :replace_all, conflict_target: [:message_id, :tag_id])

    if status == :ok do
      Communications.publish_data({status, response}, :created_message_tag)
      {:ok, response}
    else
      {:error, response}
    end
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
  In Join tables we rarely use the table id. We always know the object ids
  and hence more convenient to delete an entry via its object ids.
  We will generalize this function and move it to Repo.ex when we get a better
  handle on how to do so :)
  """
  @spec delete_message_tag_by_ids(integer, []) :: {integer(), nil | [term()]}
  def delete_message_tag_by_ids(message_id, tag_ids) when is_list(tag_ids) do
    query =
      MessageTag
      |> where([m], m.message_id == ^message_id and m.tag_id in ^tag_ids)

    Repo.all(query)
    |> publish_delete_message

    Repo.delete_all(query)
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
    {status, response} =
      %ContactTag{}
      |> ContactTag.changeset(attrs)
      |> Repo.insert(on_conflict: :replace_all, conflict_target: [:contact_id, :tag_id])

    if status == :ok do
      Communications.publish_data(response, :created_contact_tag)
      {:ok, response}
    else
      {:error, response}
    end
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
  Returns an `%Ecto.Changeset{}` for tracking contact changes.

  ## Examples

      iex> change_contact_tag(contact_tag)
      %Ecto.Changeset{data: %ContactTag{}}

  """
  @spec change_contact_tag(ContactTag.t(), map()) :: Ecto.Changeset.t()
  def change_contact_tag(%ContactTag{} = contact_tag, attrs \\ %{}) do
    ContactTag.changeset(contact_tag, attrs)
  end

  @doc """
  Remove a specific tag from contact messages
  """
  @spec remove_tag_from_all_message(integer(), String.t()) :: list()
  def remove_tag_from_all_message(contact_id, tag_shortcode) when is_binary(tag_shortcode) do
    remove_tag_from_all_message(contact_id, [tag_shortcode])
  end

  @spec remove_tag_from_all_message(integer(), [String.t()]) :: list()
  def remove_tag_from_all_message(contact_id, tag_shortcode_list) do
    query =
      from mt in MessageTag,
        join: m in assoc(mt, :message),
        join: t in assoc(mt, :tag),
        where: m.contact_id == ^contact_id and t.shortcode in ^tag_shortcode_list

    Repo.all(query)
    |> publish_delete_message

    {_, deleted_rows} =
      select(query, [mt], [mt.message_id])
      |> Repo.delete_all()

    List.flatten(deleted_rows)
  end

  @spec publish_delete_message(list) :: {:ok}
  defp publish_delete_message([]), do: {:ok}

  defp publish_delete_message(message_tags) do
    _list =
      message_tags
      |> Enum.reduce([], fn message_tag, _acc ->
        Communications.publish_data(message_tag, :deleted_message_tag)
      end)

    {:ok}
  end

  @doc """
  Deletes a list of contact tags, each tag attached to the same contact
  """
  @spec delete_contact_tag_by_ids(integer, []) :: {integer(), nil | [term()]}
  def delete_contact_tag_by_ids(contact_id, tag_ids) when is_list(tag_ids) do
    query =
      ContactTag
      |> where([m], m.contact_id == ^contact_id and m.tag_id in ^tag_ids)

    Repo.all(query)
    |> publish_delete_contact

    Repo.delete_all(query)
  end

  @spec publish_delete_contact(list) :: {:ok}
  defp publish_delete_contact([]), do: {:ok}

  defp publish_delete_contact(contact_tags) do
    _list =
      contact_tags
      |> Enum.reduce([], fn contact_tag, _acc ->
        Communications.publish_data(contact_tag, :deleted_contact_tag)
      end)

    {:ok}
  end

  @doc """
  Creates a template tag.

  ## Examples

      iex> create_template_tag(%{field: value})
      {:ok, %Contact{}}

      iex> create_template_tag(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_template_tag(map()) :: {:ok, TemplateTag.t()} | {:error, Ecto.Changeset.t()}
  def create_template_tag(attrs \\ %{}) do
    {status, response} =
      %TemplateTag{}
      |> TemplateTag.changeset(attrs)
      |> Repo.insert(on_conflict: :replace_all, conflict_target: [:template_id, :tag_id])

    if status == :ok do
      Communications.publish_data(response, :created_template_tag)
      {:ok, response}
    else
      {:error, response}
    end
  end

  @doc """
  Deletes a list of template tags, each tag attached to the same template
  """
  @spec delete_template_tag_by_ids(integer, []) :: {integer(), nil | [term()]}
  def delete_template_tag_by_ids(template_id, tag_ids) when is_list(tag_ids) do
    query =
      TemplateTag
      |> where([m], m.template_id == ^template_id and m.tag_id in ^tag_ids)

    Repo.all(query)
    |> publish_delete_template

    Repo.delete_all(query)
  end

  @spec publish_delete_template(list) :: {:ok}
  defp publish_delete_template([]), do: {:ok}

  defp publish_delete_template(template_tags) do
    _list =
      template_tags
      |> Enum.reduce([], fn template_tag, _acc ->
        Communications.publish_data(template_tag, :deleted_template_tag)
      end)

    {:ok}
  end
end
