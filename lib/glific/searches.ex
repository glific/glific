defmodule Glific.Searches do
  @moduledoc """
  The Searches context.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Conversations.Conversation,
    Messages.Message,
    Repo,
    Search.Full,
    Searches.SavedSearch
  }

  @doc """
  Returns the list of searches.

  ## Examples

      iex> list_saved_searches()
      [%SavedSearch{}, ...]

  """
  @spec list_saved_searches(map()) :: [SavedSearch.t()]
  def list_saved_searches(args \\ %{}),
    do: Repo.list_filter(args, SavedSearch, &Repo.opts_with_label/2, &Repo.filter_with/2)

  @doc """
  Returns the count of searches, using the same filter as list_saved_searches
  """
  @spec count_saved_searches(map()) :: integer
  def count_saved_searches(args \\ %{}),
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

  # common function to build query between count and search
  @spec search_query(String.t(), map()) :: Ecto.Query.t()
  defp search_query(term, args) do
    Message
    |> select([m], m.contact_id)
    |> where([m], m.message_number == 0)
    |> order_by([m], desc: m.updated_at)
    |> Full.run(term, args)
  end

  @spec do_save_search(map()) :: SavedSearch.t() | nil
  defp do_save_search(%{save_search_input: save_search_input} = args)
       when save_search_input != nil,
       do:
         create_saved_search(%{
           label: args.save_search_input.label,
           shortcode: args.save_search_input.shortcode,
           args: Map.put(args, :save_search_input, nil)
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
      if(args.filter[:ids]) do
        args.filter[:ids]
      else
        search_query(args.filter[:term], args)
        |> Repo.all()
      end

    put_in(args, [Access.key(:filter, %{}), :ids], contact_ids)
    |> Glific.Conversations.list_conversations(count)
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
  defp saved_search_args_map(id, args),
    do:
      get_saved_search!(id)
      |> Map.get(:args)
      |> add_term(Map.get(args, :term))
      |> convert_to_atom()
end
