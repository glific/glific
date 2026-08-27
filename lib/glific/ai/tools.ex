defmodule Glific.AI.Tools do
  @moduledoc """
  The single route by which Glific AI reads an organisation's data.

  Every tool call goes through `run/3`, which is deliberately the only entry
  point: authorisation, read-only enforcement, result limits and error handling
  are applied here rather than repeated in each tool, so a new tool cannot
  forget them. If these reads are ever exposed over a transport such as MCP, the
  transport calls this function and the guarantees below still hold.

  What `run/3` guarantees:

    * **The read runs as the person who asked.** The organisation and current
      user are set from the caller's user, not inherited from whatever process
      state happens to exist. Background jobs in Glific normally install the
      organisation's *root user*, which would let the assistant read past the
      asker's permissions.
    * **Nothing can write.** The call runs inside a transaction marked
      `transaction_read_only`, so a write is refused by Postgres rather than by
      convention.
    * **Failure is data, not a crash.** Unknown tools, invalid arguments and
      exceptions all come back as `{:error, message}` for the model to read.
    * **Results are bounded**, so one query cannot exhaust the context window.
  """

  require Logger

  alias Glific.{Repo, SafeLog, Users.User}

  @tools [
    Glific.AI.Tools.ListFlows,
    Glific.AI.Tools.GetFlow,
    Glific.AI.Tools.FlowStatus,
    Glific.AI.Tools.ListTemplates,
    Glific.AI.Tools.ListContactFields
  ]

  @max_result_bytes 20_000

  @doc """
  Every tool Glific AI may call.

  Configurable so a deployment can withhold a tool without a code change, and so
  a later skill can be given a narrower set than the default.
  """
  @spec all() :: [module()]
  def all do
    :glific
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:tools, @tools)
  end

  @doc "Looks a tool up by the name the model uses."
  @spec fetch(String.t()) :: {:ok, module()} | :error
  def fetch(name) do
    case Enum.find(all(), &(&1.name() == name)) do
      nil -> :error
      tool -> {:ok, tool}
    end
  end

  @doc """
  Runs one tool on behalf of a user.

  Always returns a tuple; it does not raise.
  """
  @spec run(String.t(), map(), User.t()) :: {:ok, term()} | {:error, String.t()}
  def run(name, args, %User{} = user) do
    with {:ok, tool} <- lookup(name),
         {:ok, validated} <- validate(tool, args) do
      execute(tool, validated, user)
    end
  end

  @spec lookup(String.t()) :: {:ok, module()} | {:error, String.t()}
  defp lookup(name) do
    case fetch(name) do
      {:ok, tool} -> {:ok, tool}
      :error -> {:error, ~s(There is no tool called "#{name}".)}
    end
  end

  @spec validate(module(), map()) :: {:ok, map()} | {:error, String.t()}
  defp validate(tool, args) do
    args
    |> Enum.map(fn {key, value} -> {to_atom(key), value} end)
    |> Enum.reject(fn {key, _} -> is_nil(key) end)
    |> NimbleOptions.validate(tool.parameters())
    |> case do
      {:ok, validated} -> {:ok, Map.new(validated)}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  # Only atoms that already exist, so a model naming a nonsense argument cannot
  # grow the atom table.
  @spec to_atom(atom() | String.t()) :: atom() | nil
  defp to_atom(key) when is_atom(key), do: key

  defp to_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  @spec execute(module(), map(), User.t()) :: {:ok, term()} | {:error, String.t()}
  defp execute(tool, args, user) do
    Repo.put_organization_id(user.organization_id)
    Repo.put_current_user(user)

    Repo.transaction(fn ->
      Repo.query!("SET LOCAL transaction_read_only = on")
      tool.run(args)
    end)
    |> case do
      {:ok, {:ok, result}} ->
        {:ok, limit(result)}

      {:ok, {:error, message}} ->
        {:error, message}

      {:error, reason} ->
        {:error, "The lookup could not be completed: #{SafeLog.safe_inspect(reason)}"}
    end
  rescue
    exception ->
      Glific.log_exception(exception)
      {:error, "The lookup failed: #{Exception.message(exception)}"}
  end

  @spec limit(term()) :: term()
  defp limit(result) when is_list(result) do
    if byte_size(SafeLog.safe_inspect(result)) > @max_result_bytes,
      do: %{truncated: true, showing: Enum.take(result, 20), of: length(result)},
      else: result
  end

  defp limit(result), do: result
end
