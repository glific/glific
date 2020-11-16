defmodule Glific.Repo do
  @moduledoc """
  A repository that maps to an underlying data store, controlled by the Postgres adapter.

  We add a few functions to make our life easier with a few helper functions that ecto does
  not provide.
  """

  alias __MODULE__

  alias Glific.Users.User

  import Ecto.Query

  use Ecto.Repo,
    otp_app: :glific,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Glific version of get, which returns a tuple with an :ok | :error as the first element
  """
  @spec fetch(Ecto.Queryable.t(), term(), Keyword.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, [String.t()]}
  def fetch(queryable, id, opts \\ []) do
    case get(queryable, id, opts) do
      nil -> {:error, ["#{queryable} #{id}", "Resource not found"]}
      resource -> {:ok, resource}
    end
  end

  @doc """
  Glific version of get_by, which returns a tuple with an :ok | :error as the first element
  """
  @spec fetch_by(Ecto.Queryable.t(), Keyword.t() | map(), Keyword.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, [String.t()]}
  def fetch_by(queryable, clauses, opts \\ []) do
    case get_by(queryable, clauses, opts) do
      nil -> {:error, ["#{queryable}", "Resource not found"]}
      resource -> {:ok, resource}
    end
  end

  @doc """
  Get map of field (typically label) to ids for easier lookup for various system objects - language, tag
  """
  @spec label_id_map(Ecto.Queryable.t(), [String.t()], non_neg_integer, atom()) :: %{
          String.t() => integer
        }
  def label_id_map(queryable, values, organization_id, field \\ :label) do
    queryable
    |> where([q], field(q, ^field) in ^values)
    |> where([q], q.organization_id == ^organization_id)
    |> select([q], [q.id, field(q, ^field)])
    |> Repo.all()
    |> Enum.reduce(%{}, fn row, acc ->
      [id, value] = row
      Map.put(acc, value, id)
    end)
  end

  @doc """
  We use this function in most list_OBJECT api's, where we process the opts
  and the filter. Centralizing this code at the top level, to make things
  cleaner
  """
  @spec list_filter(
          map(),
          atom(),
          (Ecto.Queryable.t(), %{optional(atom()) => any} -> Ecto.Queryable.t()),
          (Ecto.Queryable.t(), %{optional(atom()) => any} -> Ecto.Queryable.t()),
          Keyword.t()
        ) :: [any]
  def list_filter(args \\ %{}, object, opts_with_fn, filter_with_fn, repo_opts \\ []) do
    args
    |> list_filter_query(object, opts_with_fn, filter_with_fn)
    |> Repo.all(repo_opts)
  end

  @spec add_opts(
          Ecto.Queryable.t(),
          (Ecto.Queryable.t(), %{optional(atom()) => any} -> Ecto.Queryable.t()) | nil,
          map()
        ) :: Ecto.Queryable.t()
  defp add_opts(query, nil, _opts), do: query

  defp add_opts(query, opts_with_fn, opts),
    do:
      query
      |> opts_with_fn.(opts)
      |> limit_offset(opts)

  @doc """
  This function builds the query, and is used in places where we want to
  layer permissioning on top of the query
  """
  @spec list_filter_query(
          map(),
          atom(),
          (Ecto.Queryable.t(), %{optional(atom()) => any} -> Ecto.Queryable.t()) | nil,
          (Ecto.Queryable.t(), %{optional(atom()) => any} -> Ecto.Queryable.t())
        ) :: Ecto.Queryable.t()
  def list_filter_query(args \\ %{}, object, opts_with_fn, filter_with_fn) do
    args
    |> Enum.reduce(object, fn
      {:opts, opts}, query ->
        query |> add_opts(opts_with_fn, opts)

      {:filter, filter}, query ->
        query |> filter_with_fn.(filter)

      _, query ->
        query
    end)
  end

  @doc """
  We use this function also  in most list_OBJECT api's, where we process the
  the filter. Centralizing this code at the top level, to make things
  cleaner
  """
  @spec count_filter(
          map(),
          atom(),
          (Ecto.Queryable.t(), %{optional(atom()) => any} -> Ecto.Queryable.t()),
          Keyword.t()
        ) :: integer
  def count_filter(args \\ %{}, object, filter_with_fn, repo_opts \\ []) do
    args
    |> list_filter_query(object, nil, filter_with_fn)
    |> Repo.aggregate(:count, repo_opts)
  end

  @doc """
  Extracts the limit offset field, and adds to query
  """
  @spec limit_offset(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  def limit_offset(query, opts) do
    Enum.reduce(opts, query, fn
      {:limit, limit}, query ->
        query |> limit(^limit)

      {:offset, offset}, query ->
        query |> offset(^offset)

      _, query ->
        query
    end)
  end

  @doc """
  An empty function for objects that ignore the opts
  """
  @spec opts_with_nil(Ecto.Queryable.t(), any) :: Ecto.Queryable.t()
  def opts_with_nil(query, _opts), do: query

  @doc """
  A funtion which handles the order clause for a data type that has
  a 'name/body/label' in its schema (which is true for a fair number of Glific's
  data types)
  """
  @spec opts_with_field(
          Ecto.Queryable.t(),
          map(),
          :name | :body | :label
        ) ::
          Ecto.Queryable.t()
  def opts_with_field(query, opts, field) do
    Enum.reduce(opts, query, fn
      {:order, order}, query ->
        order_by(query, [o], {^order, fragment("lower(?)", field(o, ^field))})

      _, query ->
        query
    end)
  end

  @doc false
  @spec opts_with_label(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  def opts_with_label(query, opts), do: opts_with_field(query, opts, :label)

  @doc false
  @spec opts_with_body(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  def opts_with_body(query, opts), do: opts_with_field(query, opts, :body)

  @doc false
  @spec opts_with_name(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  def opts_with_name(query, opts), do: opts_with_field(query, opts, :name)

  # codebeat:disable[ABC, LOC]
  @doc """
  Add all the common filters here, rather than in each file
  """
  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  def filter_with(query, filter) do
    Enum.reduce(filter, query, fn
      {:name, name}, query ->
        from q in query, where: ilike(q.name, ^"%#{name}%")

      {:phone, phone}, query ->
        from q in query, where: ilike(q.phone, ^"%#{phone}%")

      {:label, label}, query ->
        from q in query, where: ilike(q.label, ^"%#{label}%")

      {:body, body}, query ->
        from q in query, where: ilike(q.body, ^"%#{body}%")

      {:shortcode, shortcode}, query ->
        from q in query, where: ilike(q.shortcode, ^"%#{shortcode}%")

      {:language, language}, query ->
        from q in query,
          join: l in assoc(q, :language),
          where: ilike(l.label, ^"%#{language}%")

      {:language_id, language_id}, query ->
        from q in query, where: q.language_id == ^language_id

      {:organization_id, organization_id}, query ->
        from q in query, where: q.organization_id == ^organization_id

      {:parent, label}, query ->
        from q in query,
          join: t in assoc(q, :parent),
          where: ilike(t.label, ^"%#{label}%")

      {:parent_id, parent_id}, query ->
        from q in query, where: q.parent_id == ^parent_id

      _, query ->
        query
    end)
  end

  @doc """
  Can we skip checking permissions for this user. This eliminates a DB call
  in many a case
  """
  @spec skip_permission? :: User.t() | true
  def skip_permission? do
    user = Glific.Repo.get_current_user()

    cond do
      is_nil(user) -> raise(RuntimeError, message: "Invalid user")
      user.is_restricted and Enum.member?(user.roles, :staff) -> user
      true -> true
    end
  end

  @doc """
  Implement permissioning support via groups. This is the basic wrapper, it uses
  a context specific permissioning wrapper to add the actual clauses
  """
  @spec add_permission(Ecto.Query.t(), (Ecto.Query.t(), User.t() -> Ecto.Query.t()), boolean()) ::
          Ecto.Query.t()
  def add_permission(query, permission_fn, skip_permission \\ false) do
    case skip_permission or skip_permission?() do
      true -> query
      user -> permission_fn.(query, user)
    end
  end

  # codebeat:enable[ABC, LOC]

  @doc """
  In Join tables we rarely use the table id. We always know the object ids
  and hence more convenient to delete an entry via its object ids.
  """
  @spec delete_relationships_by_ids(atom(), {{atom(), integer}, {atom(), [integer]}}) ::
          {integer(), nil | [term()]}
  def delete_relationships_by_ids(object, fields) do
    {{key_1, value_1}, {key_2, values_2}} = fields

    object
    |> where([m], field(m, ^key_1) == ^value_1 and field(m, ^key_2) in ^values_2)
    |> Repo.delete_all()
  end

  @doc false
  @spec default_options(atom()) :: Keyword.t()
  def default_options(_operation) do
    [organization_id: get_organization_id()]
  end

  @doc false
  @spec prepare_query(atom(), Ecto.Query.t(), Keyword.t()) :: {Ecto.Query.t(), Keyword.t()}
  def prepare_query(_operation, query, opts) do
    # Glific.stacktrace()
    cond do
      opts[:skip_organization_id] ||
        opts[:schema_migration] ||
        opts[:prefix] == "global" ||
        query.from.prefix == "global" ||
          is_sub_query?(query) ->
        {query, opts}

      organization_id = opts[:organization_id] ->
        {Ecto.Query.where(query, organization_id: ^organization_id), opts}

      true ->
        raise "expected organization_id or skip_organization_id to be set"
    end
  end

  # lets ignore all subqueries
  defp is_sub_query?(%{from: %{source: %Ecto.SubQuery{}}} = _query), do: true
  defp is_sub_query?(_query), do: false

  @organization_key {__MODULE__, :organization_id}
  @user_key {__MODULE__, :user}

  @doc false
  @spec put_organization_id(non_neg_integer) :: non_neg_integer | nil
  def put_organization_id(organization_id),
    do: Process.put(@organization_key, organization_id)

  @doc false
  @spec get_organization_id() :: non_neg_integer | nil
  def get_organization_id,
    do: Process.get(@organization_key)

  @doc false
  @spec put_current_user(User.t()) :: User.t() | nil
  def put_current_user(user),
    do: Process.put(@user_key, user)

  @doc false
  @spec get_current_user :: User.t() | nil
  def get_current_user,
    do: Process.get(@user_key)
end
