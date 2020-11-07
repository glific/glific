defmodule Glific.Flows.MessageVarParser do
  @moduledoc """
  substitute the contact fileds and result sets in the messages
  """

  @doc """
  parse the message with variables
  """
  @spec parse(String.t(), map()) :: String.t() | nil
  def parse(nil, _binding), do: ""

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

  defp bound(<<_::binary-size(1), var::binary>>, binding) do
    substitution =
      get_in(binding, String.split(var, "."))
      |> bound()

    if substitution == nil, do: "@#{var}", else: substitution
  end

  # this is for the otherfileds like @contact.fields.name which is a map of (value)
  defp bound(substitution) when is_map(substitution), do: bound(substitution["value"])

  defp bound(substitution), do: substitution

  # """
  # Convert map atom keys to strings
  # """

  @spec stringify_keys(map()) :: map() | nil
  defp stringify_keys(nil), do: nil

  defp stringify_keys(map) when is_struct(map), do: Map.from_struct(map)

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      if is_atom(k), do: {Atom.to_string(k), stringify_keys(v)}, else: {k, stringify_keys(v)}
    end)
    |> Enum.into(%{})
  end

  # Walk the list and stringify the keys of
  # of any map members
  defp stringify_keys([head | rest] = list) when is_list(list) do
    [stringify_keys(head) | stringify_keys(rest)]
  end

  defp stringify_keys(value),
    do: value

  def parse_results(body, results) do
    if String.contains?(body, "@results.") do
      Enum.reduce(
        results,
        body,
        fn {key, value}, acc ->
          key = String.downcase(key)
          value = value["input"]
          acc = String.replace(acc, "@results." <> key, value)
        end
      )
    else
      body
    end
  end

end
