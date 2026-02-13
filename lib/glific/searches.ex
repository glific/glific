defmodule Glific.Searches do
  @moduledoc """
  The Searches context.
  """

  import Ecto.Query, warn: false
  require Logger

  alias __MODULE__
  Conversations.WAConversation

  alias Glific.{
    Contacts.Contact,
    Conversations,
    Conversations.Conversation,
    Conversations.WAConversation,
    ConversationsGroup,
    Groups,
    Groups.ContactGroup,
    Groups.UserGroup,
    Groups.WAGroup,
    Messages.Message,
    Repo,
    Search.Full,
    Searches.SavedSearch,
    Searches.Search,
    Users.User,
    WAConversations,
    WAGroup.WAMessage
  }

  @search_timeout 30_000

  @doc """
  Returns the list of searches.

  ## Examples

      iex> list_saved_searches()
      [%SavedSearch{}, ...]

  """
  @spec list_saved_searches(map()) :: [SavedSearch.t()]
  def list_saved_searches(args),
    do: Repo.list_filter(args, SavedSearch, &Repo.opts_with_label/2, &filter_with/2)

  @doc """
  Returns the count of searches, using the same filter as list_saved_searches
  """
  @spec count_saved_searches(map()) :: integer
  def count_saved_searches(args),
    do: Repo.count_filter(args, SavedSearch, &Repo.filter_with/2)

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:is_reserved, is_reserved}, query ->
        from(q in query, where: q.is_reserved == ^is_reserved)

      _, query ->
        query
    end)
  end

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
    query = from(c in Contact, as: :c)

    query
    |> where([c], c.id in ^contact_ids)
    |> where([c], c.status != :blocked)
    |> select([c], c.id)
    |> Repo.add_permission(&Searches.add_permission/2)
  end

  @spec status_query(map()) :: Ecto.Query.t()
  defp status_query(opts) do
    query = from(c in Contact, as: :c)

    query
    |> where([c], c.status != :blocked)
    |> where([c], c.contact_type in ["WABA", "WABA+WA"])
    |> select([c], %{id: c.id, last_communication_at: c.last_communication_at})
    |> distinct(true)
    |> add_contact_opts(opts)
    |> Repo.add_permission(&Searches.add_permission/2)
  end

  @spec add_contact_opts(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp add_contact_opts(query, %{limit: limit, offset: offset}) do
    query
    |> limit(^limit)
    |> offset(^offset)
    |> order_by([c], desc: c.last_communication_at)
  end

  defp add_contact_opts(query, _opts) do
    # always order in descending order of most recent communications
    query
    |> order_by([c], desc: c.last_communication_at)
  end

  # codebeat:disable[ABC]
  @spec filter_status_contacts_of_organization(String.t(), map()) :: Ecto.Query.t()
  defp filter_status_contacts_of_organization("Unread", opts) do
    status_query(opts)
    |> where([c], c.is_org_read == false)
  end

  defp filter_status_contacts_of_organization("Optout", opts) do
    status_query(opts)
    |> where([c], c.status != :blocked)
    |> where([c], not is_nil(c.optout_time))
  end

  defp filter_status_contacts_of_organization("Optin", opts) do
    status_query(opts)
    |> where([c], c.status != :blocked)
    |> where([c], c.optin_status == true)
  end

  defp filter_status_contacts_of_organization("Not replied", opts) do
    status_query(opts)
    |> where([c], c.is_org_replied == false)
  end

  defp filter_status_contacts_of_organization("Not Responded", opts) do
    status_query(opts)
    |> where([c], c.is_contact_replied == false)
  end

  # codebeat:enable[ABC]

  @spec permission_query(User.t()) :: Ecto.Query.t()
  defp permission_query(user) do
    ContactGroup
    |> select([cg], cg.contact_id)
    |> join(:inner, [cg], ug in UserGroup, as: :ug, on: ug.group_id == cg.group_id)
    |> where([cg, ug: ug], ug.user_id == ^user.id)
  end

  @doc """
  Add permission specific to searches, in this case we want to restrict the visibility of
  contact ids where the contact is the main query table
  """
  @spec add_permission(Ecto.Query.t(), User.t()) :: Ecto.Query.t()
  def add_permission(query, user) do
    sub_query = permission_query(user)

    query
    |> where([c: c], c.id == ^user.contact_id or c.id in subquery(sub_query))
  end

  @spec basic_query(map()) :: Ecto.Query.t()
  defp basic_query(args) do
    query = from(c in Contact, as: :c)

    query
    |> add_message_clause(args)
    |> order_by([c: c], desc: c.last_communication_at, desc: c.id)
    |> where([c: c], c.status != :blocked)
    |> where([c: c], c.contact_type in ["WABA", "WABA+WA"])
    |> group_by([c: c], c.id)
    |> repo().add_permission(&Searches.add_permission/2)
  end

  @spec add_message_clause(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp add_message_clause(query, %{filter: filters} = _args)
       when is_map(filters) do
    if map_size(filters) > 1,
      do: query |> join(:left, [c: c], m in Message, as: :m, on: c.id == m.contact_id),
      else: query
  end

  defp add_message_clause(query, _args),
    do: query

  # codebeat:enable[ABC]

  # common function to build query between count and search
  # order by the last time there was communication with this contact
  # whether inbound or outbound
  @spec search_query(String.t(), map()) :: Ecto.Query.t()
  defp search_query(term, args) do
    basic_query(args)
    |> add_contact_opts(args.contact_opts)
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

  @spec group_ids(map()) :: list() | nil
  defp group_ids(%{filter: %{include_groups: gids}}), do: gids
  defp group_ids(%{filter: %{ids: gids}}), do: gids
  defp group_ids(%{filter: %{id: gid}}), do: [gid]

  defp group_ids(%{filter: %{group_label: group_label}}) do
    Groups.list_groups(%{filter: %{label: group_label}})
    |> Enum.map(fn group -> group.id end)
  end

  defp group_ids(_), do: nil

  @doc """
  Full text search interface via Postgres
  """
  @spec search(map(), boolean) :: [Conversation.t()] | integer
  def search(args, count \\ false)

  def search(%{filter: %{search_group: true, group_label: group_label}} = args, _count) do
    Logger.info(
      "Searches.Search/2 with : args: #{inspect(args)} group label: #{inspect(group_label)}"
    )

    ConversationsGroup.list_conversations(
      group_ids(args),
      args
    )
    |> append_conversation_id()
  end

  def search(%{filter: %{search_group: true}} = args, _count) do
    Logger.info("Searches.Search/2 with : args: #{inspect(args)}")

    ConversationsGroup.list_conversations(
      group_ids(args),
      args
    )
    |> append_conversation_id()
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

    is_status? =
      is_nil(args.filter[:id]) &&
        is_nil(args.filter[:ids]) &&
        !is_nil(args.filter[:status])

    contact_ids =
      cond do
        args.filter[:id] != nil ->
          filter_active_contacts_of_organization(args.filter.id)

        args.filter[:ids] != nil ->
          filter_active_contacts_of_organization(args.filter.ids)

        args.filter[:status] != nil ->
          filter_status_contacts_of_organization(args.filter.status, args.contact_opts)

        true ->
          search_query(args.filter[:term], args)
      end
      |> Repo.all(timeout: @search_timeout)
      |> get_contact_ids(is_status?)

    # if we don't have any contact ids at this stage
    # it means that the user did not have permission
    if contact_ids == [] do
      if count, do: 0, else: []
    else
      put_in(args, [Access.key(:filter, %{}), :ids], contact_ids)
      |> Conversations.list_conversations(count)
      |> append_conversation_id()
    end
  end

  defp append_conversation_id(conversations) do
    Enum.reduce(conversations, [], fn conversation, acc ->
      acc ++ do_append_conversation_id(conversation)
    end)
  end

  defp do_append_conversation_id(%{contact: nil, group: group} = conversation) do
    conversation
    |> Map.put(:id, "group_#{group.id}")
    |> then(&[&1])
  end

  defp do_append_conversation_id(%{contact: contact, group: nil} = conversation) do
    conversation
    |> Map.put(:id, "contact_#{contact.id}")
    |> then(&[&1])
  end

  defp do_append_conversation_id(%{wa_group: nil, group: group} = conversation),
    do: conversation |> Map.put(:id, "group_#{group.id}") |> then(&[&1])

  defp do_append_conversation_id(%{wa_group: wa_group, group: _group} = conversation),
    do: conversation |> Map.put(:id, "wa_group_#{wa_group.id}") |> then(&[&1])

  @doc """
  Full text whatsapp group search interface via Postgres
  """
  @spec wa_search(map()) :: [WAConversation.t()]
  def wa_search(%{filter: %{search_group: true, group_label: group_label}} = args) do
    Logger.info(
      "Searches.WASearch/2 with : args: #{inspect(args)} group label: #{inspect(group_label)}"
    )

    ConversationsGroup.wa_list_conversations(
      group_ids(args),
      args
    )
    |> append_conversation_id()
  end

  def wa_search(%{filter: %{search_group: true}} = args) do
    Logger.info("Searches.WASearch/2 with : args: #{inspect(args)}")

    ConversationsGroup.wa_list_conversations(
      group_ids(args),
      args
    )
    |> append_conversation_id()
  end

  def wa_search(args) do
    Logger.info("Searches.wa_Search/1 with : args: #{inspect(args)}")

    wa_group_ids =
      case filter_groups_of_organization(args.filter) do
        {true, query} ->
          wa_search_query(query, args)

        _ ->
          query = from(wa_grp in WAGroup, as: :wa_grp)

          wa_search_query(query, args)
          |> Full.run(args.filter[:term], args)
      end
      |> Repo.all(timeout: @search_timeout)

    put_in(args, [Access.key(:filter, %{}), :ids], wa_group_ids)
    |> WAConversations.list_conversations()
    |> append_conversation_id()
  end

  # codebeat:enable[ABC]

  @spec get_contact_ids(list(), boolean | nil) :: list()
  defp get_contact_ids(results, false), do: results

  defp get_contact_ids(results, true) do
    # one set of queries (status queries) return a map for each row
    # where id is a key in the map
    results
    |> Enum.map(fn data -> data.id end)
  end

  @doc """
  Search across multiple tables, and return a multiple context
  result back to the frontend. First step in emulating a whatsapp
  search
  """
  @spec search_multi(String.t(), map()) :: Search.t()
  def search_multi(term, args) do
    Logger.info("Search Multi: term: '#{term}'")
    org_id = Repo.get_organization_id()

    ## We are not showing tags on Glific frontend
    ## so we don't need to make extra query for multi search
    tags = []

    # Temporarily using a runtime configurable repo module as a failsafe
    # so we can switch between the replica and primary database in case of a failure.
    search_item_tasks = [
      Task.async(fn ->
        repo().put_process_state(org_id)
        get_filtered_contacts(term, args)
      end),
      Task.async(fn ->
        repo().put_process_state(org_id)
        get_filtered_messages_with_term(term, args)
      end),
      Task.async(fn ->
        repo().put_process_state(org_id)
        get_filtered_labeled_message(term, args)
      end)
    ]

    [contacts, messages, labels] = Task.await_many(search_item_tasks, @search_timeout + 1_000)

    Search.new(contacts, messages, tags, labels)
  end

  @doc """
  Search across multiple messages and wa_group table, and return a multiple context
  result back to the frontend. First step in emulating a whatsapp
  search
  """
  @spec wa_search_multi(String.t(), map()) :: map()
  def wa_search_multi(term, args) do
    Logger.info("WASearch Multi: term: '#{term}'")
    org_id = Repo.get_organization_id()

    search_item_tasks = [
      Task.async(fn ->
        Repo.put_process_state(org_id)
        get_filtered_wa_groups_with_term(term, args)
      end),
      Task.async(fn ->
        Repo.put_process_state(org_id)
        get_filtered_wa_messages_with_term(term, args)
      end)
    ]

    [wa_groups, wa_messages] = Task.await_many(search_item_tasks, @search_timeout + 1_000)
    %{wa_groups: wa_groups, wa_messages: wa_messages}
  end

  @spec filtered_query(map()) :: Ecto.Query.t()
  defp filtered_query(args) do
    {limit, offset} = {args.message_opts.limit, args.message_opts.offset}
    # always cap out limit to 250, in case frontend sends too many
    limit = min(limit, 250)
    query = from(m in Message, as: :m)

    query
    |> join(:left, [m: m], c in Contact, as: :c, on: m.contact_id == c.id)
    |> where([m, c: c], c.status != :blocked)
    |> repo().add_permission(&Searches.add_permission/2)
    |> limit(^limit)
    |> offset(^offset)
    |> order_by([c: c], desc: c.last_message_at)
  end

  # codebeat:disable[ABC]
  @spec get_filtered_contacts(String.t(), map()) :: list()
  defp get_filtered_contacts(term, args) do
    {limit, offset} = {args.contact_opts.limit, args.contact_opts.offset}

    # since this revolves around contacts
    args
    |> basic_query()
    |> where([c: c], ilike(c.name, ^"%#{term}%") or ilike(c.phone, ^"%#{term}%"))
    |> limit(^limit)
    |> offset(^offset)
    |> order_by([c: c], desc: c.last_message_at)
    |> repo().all(timeout: @search_timeout)
  end

  # codebeat:enable[ABC]

  @spec get_filtered_messages_with_term(String.t(), map()) :: list()
  defp get_filtered_messages_with_term(term, args) do
    filtered_query(args)
    |> where([m: m], ilike(m.body, ^"%#{term}%"))
    |> order_by([m: m], desc: m.message_number)
    |> repo().all(timeout: @search_timeout)
  end

  @spec get_filtered_labeled_message(String.t(), map()) :: list()
  defp get_filtered_labeled_message(term, args) do
    filtered_query(args)
    |> where([m: m], ilike(m.flow_label, ^"%#{term}%"))
    |> order_by([m: m], desc: m.message_number)
    |> repo().all(timeout: @search_timeout)
  end

  @spec get_filtered_wa_messages_with_term(String.t(), map()) :: list()
  defp get_filtered_wa_messages_with_term(term, args) do
    {limit, offset} = {args.wa_message_opts.limit, args.wa_message_opts.offset}

    query = from(wam in WAMessage, as: :wam)

    query
    |> order_by([wam: wam], desc: wam.inserted_at, desc: wam.id)
    |> Repo.add_permission(&Searches.add_permission/2)
    |> where([wam: wam], ilike(wam.body, ^"%#{term}%"))
    |> where([wam: wam], not is_nil(wam.wa_group_id))
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all(timeout: @search_timeout)
  end

  @spec get_filtered_wa_groups_with_term(String.t(), map()) :: list()
  defp get_filtered_wa_groups_with_term(term, args) do
    {limit, offset} = {args.wa_group_opts.limit, args.wa_group_opts.offset}

    query = from(wag in WAGroup, as: :wag)

    query
    |> order_by([wag: wag], desc: wag.last_communication_at, desc: wag.id)
    |> Repo.add_permission(&Searches.add_permission/2)
    |> where([wag: wag], ilike(wag.label, ^"%#{term}%"))
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all(timeout: @search_timeout)
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
            else: k |> Macro.underscore() |> Glific.safe_string_to_atom()

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

  @spec wa_search_query(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp wa_search_query(query, args) do
    query
    |> wa_basic_query(args)
    |> add_wa_group_opts(args.wa_group_opts)
    |> select([wa_grp: wa_grp], wa_grp.id)
  end

  @spec wa_basic_query(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp wa_basic_query(query, args) do
    query
    |> add_wa_message_clause(args)
    |> order_by([wa_grp: wa_grp], desc: wa_grp.last_communication_at, desc: wa_grp.id)
    |> group_by([wa_grp: wa_grp], wa_grp.id)
    |> Repo.add_permission(&Searches.add_permission/2)
  end

  @spec add_wa_message_clause(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp add_wa_message_clause(query, %{filter: filters} = _args)
       when is_map(filters) do
    if map_size(filters) > 1 do
      query
      |> join(:left, [wa_grp: wa_grp], wa_msg in WAMessage,
        as: :wa_msg,
        on: wa_grp.id == wa_msg.wa_group_id
      )
    else
      query
    end
  end

  defp add_wa_message_clause(query, _args),
    do: query

  @spec add_wa_group_opts(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp add_wa_group_opts(query, %{limit: limit, offset: offset}) do
    query
    |> limit(^limit)
    |> offset(^offset)
    |> order_by([wa_grp], desc: wa_grp.last_communication_at)
  end

  defp add_wa_group_opts(query, _opts) do
    # always order in descending order of most recent communications
    query
    |> order_by([wa_grp], desc: wa_grp.last_communication_at)
  end

  @spec filter_groups_of_organization(map()) :: {boolean, Ecto.Query.t()}
  defp filter_groups_of_organization(filters) do
    query = from(wa_grp in WAGroup, as: :wa_grp)

    {has_filter, query} =
      filters
      |> Enum.reduce({false, query}, fn {k, v}, query_obj ->
        {has_filter, query} = query_obj

        case {k, v} do
          {:id, id} ->
            {true, query |> where([wa_grp], wa_grp.id in [^id])}

          {:ids, ids} ->
            {true, query |> where([wa_grp], wa_grp.id in ^ids)}

          {:wa_phone_ids, wa_phone_ids} ->
            {true, query |> where([wa_grp], wa_grp.wa_managed_phone_id in ^wa_phone_ids)}

          {:term, term} ->
            {true, query |> where([wa_grp], ilike(wa_grp.label, ^"%#{term}%"))}

          _ ->
            {has_filter, query}
        end
      end)

    {has_filter, query}
  end

  @spec search_config() :: map()
  defp search_config, do: Application.fetch_env!(:glific, __MODULE__)

  @spec search_config(atom()) :: module()
  defp search_config(key), do: search_config()[key]

  defp repo(), do: search_config(:repo_module)
end
