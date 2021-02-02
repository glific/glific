defmodule Glific.Searches do
  @moduledoc """
  The Searches context.
  """

  import Ecto.Query, warn: false
  require Logger

  alias __MODULE__

  alias Glific.{
    Contacts.Contact,
    Conversations,
    Conversations.Conversation,
    ConversationsGroup,
    Groups.ContactGroup,
    Groups.UserGroup,
    Messages.Message,
    Partners,
    Repo,
    Search.Full,
    Searches.SavedSearch,
    Searches.Search,
    Tags.MessageTag,
    Tags.Tag,
    Users.User
  }

  @doc """
  Returns the list of searches.

  ## Examples

      iex> list_saved_searches()
      [%SavedSearch{}, ...]

  """
  @spec list_saved_searches(map()) :: [SavedSearch.t()]
  def list_saved_searches(args),
    do: Repo.list_filter(args, SavedSearch, &Repo.opts_with_label/2, &Repo.filter_with/2)

  @doc """
  Returns the count of searches, using the same filter as list_saved_searches
  """
  @spec count_saved_searches(map()) :: integer
  def count_saved_searches(args),
    do: Repo.count_filter(args, SavedSearch, &Repo.filter_with/2)

  @doc """
  Gets a single search.

  Raises `Ecto.NoResultsError` if the SavedSearch does not exist.

  ## Examples

      iex> get_saved_search!(123)
      %SavedSearch{}

      iex> get_saved_search!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_saved_search!(integer) :: SavedSearch.t()
  def get_saved_search!(id), do: Repo.get!(SavedSearch, id)

  @doc """
  Creates a search.

  ## Examples

      iex> create_saved_search(%{field: value})
      {:ok, %SavedSearch{}}

      iex> create_saved_search(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_saved_search(map()) :: {:ok, SavedSearch.t()} | {:error, Ecto.Changeset.t()}
  def create_saved_search(attrs) do
    %SavedSearch{}
    |> SavedSearch.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a search.

  ## Examples

      iex> update_saved_search(search, %{field: new_value})
      {:ok, %SavedSearch{}}

      iex> update_saved_search(search, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_saved_search(SavedSearch.t(), map()) ::
          {:ok, SavedSearch.t()} | {:error, Ecto.Changeset.t()}
  def update_saved_search(%SavedSearch{} = search, attrs) do
    search
    |> SavedSearch.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a search.

  ## Examples

      iex> delete_saved_search(search)
      {:ok, %SavedSearch{}}

      iex> delete_saved_search(search)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_saved_search(SavedSearch.t()) ::
          {:ok, SavedSearch.t()} | {:error, Ecto.Changeset.t()}
  def delete_saved_search(%SavedSearch{} = search) do
    Repo.delete(search)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking search changes.

  ## Examples

      iex> change_saved_search(search)
      %Ecto.Changeset{data: %Search{}}

  """
  @spec change_saved_search(SavedSearch.t(), map()) :: Ecto.Changeset.t()
  def change_saved_search(%SavedSearch{} = search, attrs \\ %{}) do
    SavedSearch.changeset(search, attrs)
  end

  @spec filter_active_contacts_of_organization(non_neg_integer() | [non_neg_integer()]) ::
          Ecto.Query.t()
  defp filter_active_contacts_of_organization(contact_id)
       when is_integer(contact_id) do
    filter_active_contacts_of_organization([contact_id])
  end

  defp filter_active_contacts_of_organization(contact_ids)
       when is_list(contact_ids) do
    Contact
    |> where([c], c.id in ^contact_ids)
    |> where([c], c.status != ^:blocked)
    |> select([c], c.id)
  end

  @doc """
  Add permissioning specific to searches, in this case we want to restrict the visibility of
  contact ids
  """
  # codebeat:disable[ABC]
  @spec add_permission(Ecto.Query.t(), User.t()) :: Ecto.Query.t()
  def add_permission(query, user) do
    sub_query =
      ContactGroup
      |> select([cg], cg.contact_id)
      |> join(:inner, [cg], ug in UserGroup, as: :ug, on: ug.group_id == cg.group_id)
      |> where([cg, ug: ug], ug.user_id == ^user.id)

    query
    |> where([m: m], m.contact_id == ^user.contact_id or m.contact_id in subquery(sub_query))
  end

  @spec basic_query(map()) :: Ecto.Query.t()
  defp basic_query(args) do
    organization_contact_id = Partners.organization_contact_id(args.filter.organization_id)

    query = from c in Contact, as: :c

    query
    |> join(:left, [c: c], m in Message,
      as: :m,
      on: c.id == m.contact_id and m.message_number == 0
    )
    |> where([c: c], c.id != ^organization_contact_id)
    |> order_by([c: c], desc: c.last_communication_at)
    |> Repo.add_permission(&Searches.add_permission/2)
  end

  # codebeat:enable[ABC]

  # common function to build query between count and search
  # order by the last time there was communication with this contact
  # whether inboound or outbound
  @spec search_query(String.t(), map()) :: Ecto.Query.t()
  defp search_query(term, args) do
    basic_query(args)
    |> select([c: c], c.id)
    |> Full.run(term, args)
  end

  @spec do_save_search(map()) :: SavedSearch.t() | nil
  defp do_save_search(%{save_search_input: save_search_input} = args)
       when save_search_input != nil,
       do:
         create_saved_search(%{
           label: args.save_search_input.label,
           shortcode: args.save_search_input.shortcode,
           args: Map.put(args, :save_search_input, nil),
           organization_id: args.filter.organization_id
         })

  defp do_save_search(_args), do: nil

  @doc """
  Full text search interface via Postgres
  """
  @spec search(map(), boolean) :: [Conversation.t()] | integer
  def search(args, count \\ false)

  def search(%{filter: %{search_group: true}} = args, _count) do
    Logger.info("Searches.Search/2 with : args: #{inspect(args)}")

    ConversationsGroup.list_conversations(
      get_in(args, [:filter, :include_groups]),
      args
    )
  end

  # codebeat:disable[ABC]
  def search(args, count) do
    # save the search if needed
    Logger.info("Searches.Search/2 with : args: #{inspect(args)}")
    do_save_search(args)

    args =
      args
      |> check_filter_for_save_search()
      |> update_args_for_count(count)

    contact_ids =
      cond do
        args.filter[:id] != nil ->
          filter_active_contacts_of_organization(args.filter.id)

        args.filter[:ids] != nil ->
          filter_active_contacts_of_organization(args.filter.ids)

        true ->
          search_query(args.filter[:term], args)
      end
      |> Repo.all()

    put_in(args, [Access.key(:filter, %{}), :ids], contact_ids)
    |> Conversations.list_conversations(count)
  end

  # codebeat:enable[ABC]

  @doc """
  Search across multiple tables, and return a multiple context
  result back to the frontend. First step in emulating a whatsapp
  search
  """
  @spec search_multi(String.t(), map()) :: Search.t()
  def search_multi(term, args) do
    Logger.info("Search Multi: term: '#{term}'")
    contacts = get_filtered_contacts(term, args)
    messages = get_filtered_messages_with_term(term, args)
    tags = get_filtered_tagged_message(term, args)
    Search.new(contacts, messages, tags)
  end

  @spec filtered_query(map()) :: Ecto.Query.t()
  defp filtered_query(args) do
    {limit, offset} = {args.message_opts.limit, args.message_opts.offset}

    query = from m in Message, as: :m

    query
    |> Repo.add_permission(&Searches.add_permission/2)
    |> limit(^limit)
    |> offset(^offset)
  end

  # codebeat:disable[ABC]
  @spec get_filtered_contacts(String.t(), map()) :: list()
  defp get_filtered_contacts(term, args) do
    {limit, offset} = {args.message_opts.limit, args.message_opts.offset}

    # since this revolves around contacts
    args
    |> basic_query()
    |> where([c: c], ilike(c.name, ^"%#{term}%") or ilike(c.phone, ^"%#{term}%"))
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  # codebeat:enable[ABC]

  @spec get_filtered_messages_with_term(String.t(), map()) :: list()
  defp get_filtered_messages_with_term(term, args) do
    filtered_query(args)
    |> where([m: m], ilike(m.body, ^"%#{term}%"))
    |> order_by([m: m], desc: m.inserted_at)
    |> Repo.all()
  end

  # codebeat:disable[ABC]
  @spec get_filtered_tagged_message(String.t(), map()) :: list()
  defp get_filtered_tagged_message(term, args) do
    filtered_query(args)
    |> join(:left, [m: m], mt in MessageTag, as: :mt, on: m.id == mt.message_id)
    |> join(:left, [mt: mt], t in Tag, as: :t, on: t.id == mt.tag_id)
    |> where([t: t], ilike(t.label, ^"%#{term}%") or ilike(t.shortcode, ^"%#{term}%"))
    |> Repo.all()
  end

  # codebeat:enable[ABC]

  # Add the term if present to the list of args
  @spec add_term(map(), String.t() | nil) :: map()
  defp add_term(args, term) when is_nil(term) or term == "", do: args
  defp add_term(args, term), do: Map.put(args, :term, term)

  @doc """
  Execute a saved search, if term is sent in, it is added to
  the saved search. Either return conversations or count
  """
  @spec saved_search_count(map()) :: [Conversation.t()] | integer
  def saved_search_count(%{id: id} = args),
    do:
      saved_search_args_map(id, args)
      |> search(true)

  @doc """
  Given a jsonb string, typically either from the database, or maybe via graphql
  convert the string keys to atoms
  """
  @spec convert_to_atom(map()) :: map()
  def convert_to_atom(json) do
    Map.new(
      json,
      fn {k, v} ->
        atom_k =
          if is_atom(k),
            do: k,
            else: k |> Macro.underscore() |> String.to_existing_atom()

        if atom_k in [:filter, :contact_opts, :message_opts],
          do: {atom_k, convert_to_atom(v)},
          else: {atom_k, v}
      end
    )
  end

  # disabling all contact filters to get the count
  @spec update_args_for_count(map(), boolean()) :: map()
  defp update_args_for_count(args, true) do
    args
    |> put_in([:contact_opts, :limit], nil)
    |> put_in([:contact_opts, :offset], nil)
  end

  defp update_args_for_count(args, false), do: args

  # Get all the filters from saved search
  @spec check_filter_for_save_search(map()) :: map()
  defp check_filter_for_save_search(%{filter: %{saved_search_id: id}} = args),
    do: saved_search_args_map(id, args)

  defp check_filter_for_save_search(args), do: args

  # Get the args map from the saved search and override the term
  @spec saved_search_args_map(integer(), map) :: map()
  defp saved_search_args_map(id, args) do
    saved_search = get_saved_search!(id)

    saved_search
    |> Map.get(:args)
    |> add_term(Map.get(args, :term))
    |> convert_to_atom()
    |> put_in([:filter, :organization_id], saved_search.organization_id)
  end
end
