defmodule Glific.Searches do
  @moduledoc """
  The Searches context.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Conversations.Conversation,
    Groups.ContactGroup,
    Groups.UserGroup,
    Messages.Message,
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
  def list_saved_searches(%{filter: %{organization_id: _organization_id}} = args),
    do: Repo.list_filter(args, SavedSearch, &Repo.opts_with_label/2, &Repo.filter_with/2)

  @doc """
  Returns the count of searches, using the same filter as list_saved_searches
  """
  @spec count_saved_searches(map()) :: integer
  def count_saved_searches(%{filter: %{organization_id: _organization_id}} = args),
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

  @spec filter_active_contacts_of_organization(
          non_neg_integer() | [non_neg_integer()],
          non_neg_integer()
        ) :: Ecto.Query.t()
  defp filter_active_contacts_of_organization(contact_id, organization_id)
       when is_integer(contact_id) do
    filter_active_contacts_of_organization([contact_id], organization_id)
  end

  defp filter_active_contacts_of_organization(contact_ids, organization_id)
       when is_list(contact_ids) do
    Contact
    |> where([c], c.id in ^contact_ids)
    |> where([c], c.organization_id == ^organization_id)
    |> where([c], c.status != ^:blocked)
    |> select([c], c.id)
  end

  @spec get_restricted_permission(Ecto.Query.t(), User.t()) :: Ecto.Query.t()
  defp get_restricted_permission(query, user) do
    # for now we'll just give access to odd contacts for odd users
    # and even contacts for even users
    query
    |> join(:inner, [m], ug in UserGroup, as: :ug, on: ug.user_id == ^user.id)
    |> join(:inner, [m, ug: ug], cg in ContactGroup, as: :cg, on: ug.group_id == cg.group_id)
    |> where([m, cg: cg], m.contact_id == cg.contact_id)
  end

  @spec get_permission(Ecto.Query.t()) :: Ecto.Query.t()
  defp get_permission(query) do
    user = Glific.Repo.get_current_user()

    if is_nil(user), do: raise(RuntimeError, message: "Invalid user")

    if user.is_restricted and Enum.member?(user.roles, :staff),
      do: get_restricted_permission(query, user),
      else: query
  end

  # common function to build query between count and search
  # order by inserted_at instead of updated_at for order of conversations list
  # so that conversation with latest message will be on the top
  @spec search_query(String.t(), map()) :: Ecto.Query.t()
  defp search_query(term, args) do
    Message
    |> select([m], m.contact_id)
    |> where([m], m.message_number == 0)
    |> where([m], m.organization_id == ^args.filter.organization_id)
    |> order_by([m], desc: m.inserted_at)
    |> get_permission()
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
  def search(args, count \\ false) do
    # save the search if needed
    do_save_search(args)

    args =
      check_filter_for_save_search(args)
      |> update_args_for_count(count)

    contact_ids =
      cond do
        args.filter[:id] != nil ->
          filter_active_contacts_of_organization(args.filter.id, args.filter.organization_id)

        args.filter[:ids] != nil ->
          filter_active_contacts_of_organization(args.filter.ids, args.filter.organization_id)

        true ->
          search_query(args.filter[:term], args)
      end
      |> Repo.all()

    put_in(args, [Access.key(:filter, %{}), :ids], contact_ids)
    |> Glific.Conversations.list_conversations(count)
  end

  @doc """
  Search across multiple tables, and return a multiple context
  result back to the frontend. First step in emulating a whatsapp
  search
  """
  @spec search_multi(String.t(), map()) :: Search.t()
  def search_multi(term, args) do
    contacts = get_filtered_contacts(term, args)
    messages = get_filtered_messages_with_term(term, args)
    tags = get_filtered_tagged_message(term, args)
    Search.new(contacts, messages, tags)
  end

  defp get_filtered_contacts(term, args) do
    {limit, offset} = {args.message_opts.limit, args.message_opts.offset}

    Message
    # we are only interested in the latest message
    |> where([m], m.organization_id == ^args.filter.organization_id and m.message_number == 0)
    |> join(:inner, [m], c in Contact, as: :contact, on: c.id == m.contact_id)
    |> where([contact: c], ilike(c.name, ^"%#{term}%") or ilike(c.phone, ^"%#{term}%"))
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  defp get_filtered_messages_with_term(term, args) do
    {limit, offset} = {args.message_opts.limit, args.message_opts.offset}

    Message
    |> where([m], m.organization_id == ^args.filter.organization_id)
    |> where([m], ilike(m.body, ^"%#{term}%"))
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  defp get_filtered_tagged_message(term, args) do
    {limit, offset} = {args.message_opts.limit, args.message_opts.offset}

    Message
    |> where([m], m.organization_id == ^args.filter.organization_id)
    |> join(:left, [m], mt in MessageTag, as: :mt, on: m.id == mt.message_id)
    |> join(:left, [mt: mt], t in Tag, as: :t, on: t.id == mt.tag_id)
    |> where([t: t], ilike(t.label, ^"%#{term}%") or ilike(t.shortcode, ^"%#{term}%"))
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

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
