defmodule Glific.AI.Tools do
  @moduledoc """
  The single route by which Glific AI reads an organisation's data.

  Every tool call goes through `run/4`, the only entry point: authorisation,
  read-only enforcement and error handling are applied here rather than repeated
  in each tool, so a new tool cannot forget them.

  What `run/4` guarantees:

    * **The read runs as the person who asked.** The caller's `organization_id`
        and `user` are put into the Repo.
    * **Failure is data, not a crash.** Unknown tools, invalid arguments and
      exceptions all come back as `{:error, message}` for the model to read.
    * **Results are bounded.** Each tool clamps its own `limit`, and the agent's
      step and cost ceilings bound a whole run.
  """

  alias Glific.{AI.Tool, Repo, SafeLog, Users.User}

  @modules [
    Glific.AI.Tools.Flows,
    Glific.AI.Tools.Templates,
    Glific.AI.Tools.Contacts,
    Glific.AI.Tools.Messages,
    Glific.AI.Tools.Organization,
    Glific.AI.Tools.Reference,
    Glific.AI.Tools.Triggers,
    Glific.AI.Tools.Assistants,
    Glific.AI.Tools.Groups,
    Glific.AI.Tools.Forms
  ]

  @doc "Every feature module Glific AI reads through."
  @spec modules() :: [module()]
  def modules, do: @modules

  @doc "Every operation, flattened across the feature modules, as the model sees them."
  @spec all() :: [Tool.spec()]
  def all, do: Enum.flat_map(modules(), & &1.specs())

  @doc "Looks an operation up by the name the model uses."
  @spec fetch(String.t(), [module()]) :: {:ok, {module(), Tool.spec()}} | :error
  def fetch(name, modules \\ modules()) do
    Enum.find_value(modules, :error, fn module ->
      case Enum.find(module.specs(), &(&1.name == name)) do
        nil -> nil
        spec -> {:ok, {module, spec}}
      end
    end)
  end

  @doc """
  Runs one tool on behalf of a user.

  Always returns a tuple; it does not raise.
  """
  @spec run(String.t(), map(), User.t(), [module()]) :: {:ok, term()} | {:error, String.t()}
  def run(name, args, %User{} = user, modules \\ modules()) do
    with {:ok, {module, spec}} <- lookup(name, modules),
         {:ok, validated} <- validate(spec, args) do
      execute(module, name, validated, user)
    end
  end

  @spec lookup(String.t(), [module()]) :: {:ok, {module(), Tool.spec()}} | {:error, String.t()}
  defp lookup(name, modules) do
    case fetch(name, modules) do
      {:ok, found} -> {:ok, found}
      :error -> {:error, ~s(There is no tool called "#{name}".)}
    end
  end

  @spec validate(Tool.spec(), map()) :: {:ok, map()} | {:error, String.t()}
  defp validate(spec, args) do
    with {:ok, keyword} <- to_keyword(spec, args),
         {:ok, validated} <- NimbleOptions.validate(keyword, spec.parameters) do
      {:ok, Map.new(validated)}
    else
      {:error, %NimbleOptions.ValidationError{} = error} -> {:error, Exception.message(error)}
      {:error, message} -> {:error, message}
    end
  end

  @spec to_keyword(Tool.spec(), map()) :: {:ok, keyword()} | {:error, String.t()}
  defp to_keyword(spec, args) do
    {known, unknown} =
      args
      |> Enum.map(fn {key, value} -> {to_atom(key), key, value} end)
      |> Enum.split_with(fn {atom, _given, _value} -> not is_nil(atom) end)

    case unknown do
      [] -> {:ok, Enum.map(known, fn {atom, _given, value} -> {atom, value} end)}
      _ -> {:error, unknown_arguments(spec, unknown)}
    end
  end

  @spec unknown_arguments(Tool.spec(), [{nil, term(), term()}]) :: String.t()
  defp unknown_arguments(spec, unknown) do
    named = Enum.map_join(unknown, ", ", fn {_atom, given, _value} -> ~s("#{given}") end)
    valid = spec.parameters |> Keyword.keys() |> Enum.map_join(", ", &to_string/1)

    "#{spec.name} has no argument #{named}. Valid arguments: #{valid}."
  end

  @spec to_atom(atom() | String.t()) :: atom() | nil
  defp to_atom(key) when is_atom(key), do: key

  defp to_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  @spec execute(module(), String.t(), map(), User.t()) :: {:ok, term()} | {:error, String.t()}
  defp execute(module, name, args, user) do
    caller = {Repo.get_organization_id(), Repo.get_current_user()}

    Repo.put_organization_id(user.organization_id)
    Repo.put_current_user(user)

    try do
      read(module, name, args)
    rescue
      exception ->
        Glific.log_exception(exception)
        {:error, "The lookup failed: #{Exception.message(exception)}"}
    after
      restore(caller)
    end
  end

  @spec read(module(), String.t(), map()) :: {:ok, term()} | {:error, String.t()}
  defp read(module, name, args) do
    Repo.transaction(fn ->
      Repo.query!("SET LOCAL transaction_read_only = on")
      module.run(name, args)
    end)
    |> case do
      {:ok, {:ok, result}} ->
        {:ok, result}

      {:ok, {:error, message}} ->
        {:error, message}

      {:error, reason} ->
        {:error, "The lookup could not be completed: #{SafeLog.safe_inspect(reason)}"}
    end
  end

  @spec restore({non_neg_integer() | nil, User.t() | nil}) :: :ok
  defp restore({organization_id, user}) do
    Repo.put_organization_id(organization_id)
    Repo.put_current_user(user)
    :ok
  end
end
