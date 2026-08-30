defmodule Glific.AI.Tools do
  @moduledoc """
  The only route by which Glific AI reads an organisation's data.

  Every tool call goes through `run/3`, so these hold for all tools rather than
  being repeated in each one:

    * the read runs as the user who asked, set here rather than inherited from
      whatever the process state happens to hold
    * nothing can write — the call runs in a `transaction_read_only`
      transaction, so Postgres refuses a write
    * unknown tools, invalid arguments and exceptions return `{:error, message}`
      for the model to read, rather than ending the run
    * results are size-capped, so one query cannot fill the context window
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

  # Existing atoms only: a model naming a nonsense argument must not grow the
  # atom table.
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
