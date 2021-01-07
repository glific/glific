defmodule Glific.Flows.MessageVarParser do
  require Logger

  @moduledoc """
  substitute the contact fileds and result sets in the messages
  """

  @doc """
  parse the message with variables
  """
  @spec parse(String.t(), map()) :: String.t() | nil
  def parse(nil, _binding), do: ""

  def parse(input, binding) when binding in [nil, %{}], do: input

  def parse(input, binding) do
    binding = stringify_keys(binding)

    input
    |> String.replace(~r/@[\w]+[\.][\w]+[\.][\w]*/, &bound(&1, binding))
    |> String.replace(~r/@[\w]+[\.][\w]*/, &bound(&1, binding))
  end

  @spec bound(String.t(), map()) :: String.t()
  defp bound(nil, _binding), do: ""

  # We need to figure out a way to replace these kind of variables
  defp bound("@contact.language", binding) do
    language = get_in(binding, ["contact", "fields", "language"])
    language["label"]
  end

  # since this is a list we need to convert that into a string.
  defp bound("@contact.in_groups", binding) do
    "#{inspect(get_in(binding, ["contact", "in_groups"]))}"
  end

  defp bound(<<_::binary-size(1), var::binary>>, binding) do
    substitution =
      get_in(binding, String.split(var, "."))
      |> bound()

    if substitution == nil, do: "@#{var}", else: substitution
  rescue
    FunctionClauseError ->
      error = "get_in threw an exception, var: #{var}, binding: #{binding}"
      Logger.error(error)
      Appsignal.send_error(FunctionClauseError, error, __STACKTRACE__)
      "@#{var}"
  end

  # this is for the otherfileds like @contact.fields.name which is a map of (value)
  defp bound(substitution) when is_map(substitution), do: bound(substitution["value"])

  defp bound(substitution), do: substitution

  # """
  # Convert map atom keys to strings
  # """

  @spec stringify_keys(map()) :: map() | nil
  defp stringify_keys(nil), do: nil

  defp stringify_keys(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp stringify_keys(map) when is_struct(map), do: Map.from_struct(map)
  defp stringify_keys(int) when is_integer(int), do: Integer.to_string(int)
  defp stringify_keys(float) when is_float(float), do: Float.to_string(float)

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {stringify_keys(k), stringify_keys(v)} end)
    |> Enum.into(%{})
  end

  # Walk the list and stringify the keys of
  # of any map members
  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys(&1))

  defp stringify_keys(value), do: value

  @doc """
  Interpolates the values from results into the message body.
  Might need to integrate it with the substitution above.
  It will just treat @results.variable to @results.variable.input
  """
  @spec parse_results(String.t(), map()) :: String.t()
  def parse_results(body, results) do
    if String.contains?(body, "@results.") do
      Enum.reduce(
        results,
        body,
        fn {key, value}, acc ->
          key = String.downcase(key)

          if Map.has_key?(value, "input") and !is_map(value["input"]) do
            value = to_string(value["input"])
            String.replace(acc, "@results." <> key, value)
          else
            acc
          end
        end
      )
    else
      body
    end
  end
end
