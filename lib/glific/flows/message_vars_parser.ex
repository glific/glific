defmodule Glific.Flows.MessageVarParser do
  @moduledoc """
  substitute the contact fields and result sets in the messages
  """
  require Logger

  alias Glific.{
    Partners,
    Repo
  }

  @doc """
  parse the message with variables
  """
  @spec parse(String.t(), map()) :: String.t() | nil
  def parse(nil, _binding), do: ""

  def parse(input, binding) when binding in [nil, %{}], do: input

  def parse(input, binding) when is_map(binding) == false, do: input

  def parse(input, binding) do
    parser_types = ["@global", "@calendar"]

    binding =
      Enum.reduce(parser_types, binding, fn key, acc ->
        if String.contains?(input, key), do: load_vars(acc, key), else: acc
      end)
      |> stringify_keys()

    input
    |> String.replace(
      ~r/@[\w\-]+[\.][\w\-]+[\.][\w\-]+[\.][\w\-]+[\.][\w\-]*/,
      &bound(&1, binding)
    )
    |> String.replace(~r/@[\w\-]+[\.][\w\-]+[\.][\w\-]+[\.][\w\-]*/, &bound(&1, binding))
    |> String.replace(~r/@[\w\-]+[\.][\w\-]+[\.][\w\-]*/, &bound(&1, binding))
    |> String.replace(~r/@[\w\-]+[\.][\w\-]*/, &bound(&1, binding))
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

  # this is for the other fields like @contact.fields.name which is a map of (value)
  defp bound(substitution) when is_map(substitution) do
    # this is a hack to detect if it a calendar object, and if so, we get the
    # string value. Might need a better solution. This is specifically for inserted_at
    # for now, but generalized so it can handle all datetime objects
    if Map.has_key?(substitution, :calendar),
      do: DateTime.to_string(substitution),
      else: bound(substitution["value"])
  end

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

  @spec do_parse_one(String.t(), String.t(), map(), String.t()) :: String.t()
  defp do_parse_one(body, replace_prefix, results, key) do
    value = results[key]
    key = String.downcase(key)

    if is_map(value) && Map.has_key?(value, "input") && !is_map(value["input"]) do
      replace = to_string(value["input"])
      String.replace(body, replace_prefix <> key, replace)
    else
      body
    end
  end

  @spec do_parse_results(String.t(), String.t(), map()) :: String.t()
  defp do_parse_results(body, replace_prefix, results) when is_map(results) do
    if String.contains?(body, replace_prefix),
      do:
        results
        |> Map.keys()
        # Sort the keys so we process the larger keys first. this ensures that
        # we handle a key like 'greeting_details' before 'greeting'
        # Issue #1862
        |> Enum.sort(&(byte_size(&1) >= byte_size(&2)))
        |> Enum.reduce(
          body,
          &do_parse_one(&2, replace_prefix, results, &1)
        ),
      else: body
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

  def parse_map(value, bindings) when is_list(value),
    do: Enum.map(value, &parse_map(&1, bindings))

  def parse_map(value, bindings) when is_binary(value),
    do: parse(value, bindings) |> parse_results(bindings["results"])

  def parse_map(value, _results), do: value

  defp load_vars(binding, "@global") do
    global_vars =
      Repo.get_organization_id()
      |> Partners.get_global_field_map()

    Map.put(binding, "global", global_vars)
  end

  defp load_vars(binding, "@calendar") do
    default_format = "{D}/{0M}/{YYYY}"
    today = Timex.today()

    calendar_vars = %{
      current_date: today |> Timex.format!(default_format) |> to_string(),
      yesterday: Timex.shift(today, days: -1) |> Timex.format!(default_format) |> to_string(),
      tomorrow: Timex.shift(today, days: 1) |> Timex.format!(default_format) |> to_string(),
      current_day: today |> Timex.weekday() |> Timex.day_name() |> String.downcase(),
      current_month: Timex.now().month |> Timex.month_name() |> String.downcase(),
      current_year: Timex.now().year
    }

    Map.put(binding, "calendar", calendar_vars)
  end

  defp load_vars(binding, _), do: binding
end
