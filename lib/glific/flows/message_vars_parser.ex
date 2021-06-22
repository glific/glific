defmodule Glific.Flows.MessageVarParser do
  require Logger

  alias Glific.{
    Partners,
    Repo
  }

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
    binding =
      binding
      |> Map.put(
        "global",
        Partners.get_global_field_map(Repo.get_organization_id())
      )
      |> stringify_keys()

    input
    |> String.replace(~r/@[\w]+[\.][\w]+[\.][\w]+[\.][\w]*/, &bound(&1, binding))
    |> String.replace(~r/@[\w]+[\.][\w]+[\.][\w]*/, &bound(&1, binding))
    |> String.replace(~r/@[\w]+[\.][\w]*/, &bound(&1, binding))
    |> parse_results(binding["results"])
  end

  @spec bound(String.t(), map()) :: String.t()
  defp bound(nil, _binding), do: ""

  defp bound(str, nil), do: str

  # We need to figure out a way to replace these kind of variables
  defp bound("@contact.language", binding) do
    language = get_in(binding, ["contact", "fields", "language"])
    language["label"]
  end

  defp bound("@contact.groups", binding),
  do: bound("@contact.in_groups", binding)

  # since this is a list we need to convert that into a string.
  defp bound("@contact.in_groups", binding) do
    "#{inspect(get_in(binding, ["contact", "in_groups"]))}"
  end

  defp bound(<<_::binary-size(1), var::binary>>, binding) do
    var = String.replace_trailing(var, ".", "")

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
  defp stringify_keys(""), do: nil

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
  def parse_results(body, results) when is_map(results) do
    body
    |> do_parse_results("@results.", results)
    |> do_parse_results("@results.parent.", results["parent"])
    |> do_parse_results("@results.child.", results["child"])
  end

  def parse_results(body, _), do: body

  @spec do_parse_results(String.t(), String.t(), map()) :: String.t()
  defp do_parse_results(body, replace_prefix, results) when is_map(results) do
    if String.contains?(body, replace_prefix) do
      Enum.reduce(
        results,
        body,
        fn
          {key, value}, acc ->
            key = String.downcase(key)

            if Map.has_key?(value, "input") and !is_map(value["input"]) do
              value = to_string(value["input"])
              String.replace(acc, replace_prefix <> key, value)
            else
              acc
            end
        end
      )
    else
      body
    end
  end

  defp do_parse_results(body, _replace_prefix, _results), do: body

  @doc """
  Replace all the keys and values of a given map
  """
  @spec parse_map(map(), map()) :: map()
  def parse_map(map, bindings) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {parse_map(k, bindings), parse_map(v, bindings)} end)
    |> Enum.into(%{})
  end

  def parse_map(value, bindings) when is_binary(value),
    do: parse(value, bindings) |> parse_results(bindings["results"])

  def parse_map(value, _results), do: value
end
