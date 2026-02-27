# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks
# Since we are injecting a complete module, keeping it as it is, is more readable than splitting as multiple macros
defmodule Glific.RepoHelpers do
  @moduledoc """
  We add a few functions to make our life easier with a few helper functions that ecto does
  not provide which will be used by `Glific.Repo` and `Glific.RepoReplica`.
  """

  defmacro __using__(_) do
    quote do
      alias __MODULE__

      alias Glific.{Partners, Users.User}
      use Publicist

      import Ecto.Query
      require Logger

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
        |> __MODULE__.all()
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
              Ecto.Queryable.t(),
              (Ecto.Queryable.t(), %{optional(atom()) => any} -> Ecto.Queryable.t()),
              (Ecto.Queryable.t(), %{optional(atom()) => any} -> Ecto.Queryable.t()),
              Keyword.t()
            ) :: [any]
      def list_filter(args \\ %{}, object, opts_with_fn, filter_with_fn, repo_opts \\ []) do
        args
        |> list_filter_query(object, opts_with_fn, filter_with_fn)
        |> __MODULE__.all(repo_opts)
      rescue
        Postgrex.Error ->
          error =
            "list_filter threw an exception, args: #{inspect(args)}, object: #{inspect(object)}"

          Logger.error(error)
          Appsignal.send_error(:error, error, __STACKTRACE__)
          []
      end

      @doc false
      @spec add_opts(
              Ecto.Queryable.t(),
              (Ecto.Queryable.t(), %{optional(atom()) => any} -> Ecto.Queryable.t()) | nil,
              map()
            ) :: Ecto.Queryable.t()
      def add_opts(query, nil, _opts), do: query

      def add_opts(query, opts_with_fn, opts),
        do:
          query
          |> opts_with_fn.(opts)
          |> limit_offset(opts)

      @doc """
      This function builds the query, and is used in places where we want to
      layer permission on top of the query
      """
      @spec list_filter_query(
              map(),
              Ecto.Queryable.t(),
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
              Ecto.Queryable.t(),
              (Ecto.Queryable.t(), %{optional(atom()) => any} -> Ecto.Queryable.t()),
              Keyword.t()
            ) :: integer
      def count_filter(args \\ %{}, object, filter_with_fn, repo_opts \\ []) do
        args
        |> list_filter_query(object, nil, filter_with_fn)
        |> __MODULE__.aggregate(:count, repo_opts)
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
      A function which handles the order clause for a data type that has
      a 'name/body/label' in its schema (which is true for a fair number of Glific's
      data types)
      """
      @spec opts_with_field(
              Ecto.Queryable.t(),
              map(),
              :name | :body | :label | :inserted_at | :id
            ) :: Ecto.Queryable.t()
      def opts_with_field(query, opts, field) do
        sort =
          Enum.reduce(
            opts,
            %{},
            fn
              {:order, order}, acc ->
                acc
                |> Map.put(:order, order)
                |> Map.put_new(:with, field)

              {:order_with, field}, acc ->
                Map.put(acc, :with, Glific.safe_string_to_atom(field))

              _, acc ->
                acc
            end
          )

        if Map.has_key?(sort, :order) do
          order = sort.order
          real_field = sort.with

          cond do
            field == :inserted_at ->
              order_by(query, [o], {^order, field(o, ^real_field)})

            field == :id ->
              order_by(query, [o], {^order, field(o, ^real_field)})

            field == real_field ->
              order_by(query, [o], {^order, fragment("lower(?)", field(o, ^real_field))})

            field != real_field ->
              order_by(query, [o], {^order, field(o, ^real_field)})
          end
        else
          query
        end
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

      @doc false
      @spec opts_with_inserted_at(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
      def opts_with_inserted_at(query, opts), do: opts_with_field(query, opts, :inserted_at)

      @doc false
      @spec opts_with_id(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
      def opts_with_id(query, opts), do: opts_with_field(query, opts, :id)

      @doc false
      @spec make_like(Ecto.Queryable.t(), atom(), String.t() | nil) :: Ecto.Queryable.t()
      def make_like(query, _name, str) when is_nil(str) or str == "",
        do: query

      def make_like(query, name, str),
        do: from(q in query, where: ilike(field(q, ^name), ^"%#{str}%"))

      @spec end_of_day(DateTime.t()) :: DateTime.t()
      defp end_of_day(date),
        do:
          date
          |> Timex.to_datetime()
          |> Timex.end_of_day()

      # Filter based on the date range
      @spec filter_with_date_range(
              Ecto.Queryable.t(),
              DateTime.t() | nil,
              DateTime.t() | nil,
              atom()
            ) ::
              Ecto.Queryable.t()

      defp filter_with_date_range(query, from, to, column_name) do
        cond do
          is_nil(from) && is_nil(to) ->
            query

          is_nil(from) && not is_nil(to) ->
            where(query, [q], field(q, ^column_name) <= ^end_of_day(to))

          not is_nil(from) && is_nil(to) ->
            where(query, [q], field(q, ^column_name) >= ^Timex.to_datetime(from))

          true ->
            where(
              query,
              [q],
              field(q, ^column_name) >= ^Timex.to_datetime(from) and
                field(q, ^column_name) <= ^end_of_day(to)
            )
        end
      end

      # codebeat:disable[ABC, LOC]
      @doc """
      Add all the common filters here, rather than in each file
      """
      @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
      def filter_with(query, filter) do
        Enum.reduce(filter, query, fn
          {:name, name}, query ->
            make_like(query, :name, name)

          {:phone, phone}, query ->
            make_like(query, :phone, phone)

          {:label, label}, query ->
            make_like(query, :label, label)

          {:body, body}, query ->
            make_like(query, :body, body)

          {:shortcode, shortcode}, query ->
            from(q in query, where: q.shortcode == ^shortcode)

          {:language, language}, query ->
            from(q in query,
              join: l in assoc(q, :language),
              where: ilike(l.label, ^"%#{language}%")
            )

          {:language_id, language_id}, query ->
            from(q in query, where: q.language_id == ^language_id)

          {:organization_id, organization_id}, query ->
            from(q in query, where: q.organization_id == ^organization_id)

          {:parent, label}, query ->
            from(q in query,
              join: t in assoc(q, :parent),
              where: ilike(t.label, ^"%#{label}%")
            )

          {:parent_id, parent_id}, query ->
            from(q in query, where: q.parent_id == ^parent_id)

          {:date_range, dates}, query ->
            column_name =
              (dates[:column] || :inserted_at)
              |> Glific.safe_string_to_atom(:inserted_at)

            filter_with_date_range(query, dates[:from], dates[:to], column_name)

          _, query ->
            query
        end)
      end

      @doc """
      Can we skip checking permissions for this user. This eliminates a DB call
      in many a case
      """
      @spec skip_permission?(User.t() | nil) :: boolean()
      def skip_permission?(user \\ get_current_user()) do
        cond do
          is_nil(user) -> raise(RuntimeError, message: "Invalid user")
          user.is_restricted and Enum.member?(user.roles, :staff) -> false
          true -> true
        end
      end

      @doc """
      Implement permission support via groups. This is the basic wrapper, it uses
      a context specific permission wrapper to add the actual clauses
      """
      @spec add_permission(
              Ecto.Query.t(),
              (Ecto.Query.t(), User.t() -> Ecto.Query.t()),
              boolean()
            ) ::
              Ecto.Query.t()
      def add_permission(query, permission_fn, skip_permission \\ false) do
        user = get_current_user()

        if skip_permission || skip_permission?(user),
          do: query,
          else: permission_fn.(query, user)
      end

      @doc false
      @impl true
      @spec default_options(atom()) :: Keyword.t()
      def default_options(_operation) do
        [organization_id: get_organization_id()]
      end

      @doc false
      @impl true
      @spec prepare_query(atom(), Ecto.Query.t(), Keyword.t()) :: {Ecto.Query.t(), Keyword.t()}
      def prepare_query(_operation, query, opts) do
        cond do
          opts[:skip_organization_id] ||
            opts[:schema_migration] ||
            opts[:prefix] == "global" ||
            query.from.prefix == "global" ||
              sub_query?(query) ->
            {query, opts}

          organization_id = opts[:organization_id] ->
            {Ecto.Query.where(query, organization_id: ^organization_id), opts}

          true ->
            raise "expected organization_id or skip_organization_id to be set"
        end
      end

      # lets ignore all sub queries
      @spec sub_query?(Ecto.Query.t()) :: boolean()
      defp sub_query?(%{from: %{source: %Ecto.SubQuery{}}} = _query), do: true
      defp sub_query?(_query), do: false

      @organization_key {__MODULE__, :organization_id}
      @user_key {__MODULE__, :user}

      @doc false
      @spec put_organization_id(non_neg_integer) :: non_neg_integer | nil
      def put_organization_id(organization_id) do
        Logger.metadata(org_id: organization_id)
        Process.put(@organization_key, organization_id)
      end

      @doc false
      @spec get_organization_id() :: non_neg_integer | nil
      def get_organization_id,
        do: Process.get(@organization_key)

      @doc false
      @spec put_current_user(User.t()) :: User.t() | nil
      def put_current_user(user) do
        Logger.metadata(user_id: user.id)
        Process.put(@user_key, user)
      end

      @doc false
      @spec get_current_user :: User.t() | nil
      def get_current_user,
        do: Process.get(@user_key)

      @doc false
      @spec put_process_state(non_neg_integer) :: non_neg_integer
      def put_process_state(organization_id) do
        put_organization_id(organization_id)
        put_current_user(Partners.organization(organization_id).root_user)
        organization_id
      end
    end
  end
end
