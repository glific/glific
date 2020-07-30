defmodule Glific.Flows.MessageVarParser do
  @moduledoc """
  substitute the contact fileds and result sets in the messages
  """

  @doc """
  parse the message with variables
  """
  @spec parse(String.t(), map()) :: String.t() | nil
  def parse(input, binding) do
    binding = stringify_keys(binding)

    String.replace(input, ~r/@[\w]+[\.][\w]+[\.][\w]*/, &bound(&1, binding))
    |> String.replace(~r/@[\w]+[\.][\w]*/, &bound(&1, binding))
  end

  @spec bound(String.t(), map()) :: String.t()
  defp bound(nil, _binding), do: ""

  # We need to figure out a way to replace these kind of variables
  defp bound("@contact.language", binding) do
    language = get_in(binding, ["contact", "fields", "language"])
    language["label"]
  end

  defp bound("@contact.phone", binding) do
    phone = get_in(binding, ["contact", "fields", "phone"])
    phone
  end

  defp bound(<<_::binary-size(1), var::binary>>, binding) do
    substitution = get_in(binding, String.split(var, "."))
    if substitution == nil, do: "@#{var}", else: substitution
  end

  # """
  # Convert map atom keys to strings
  # """

  @spec stringify_keys(map()) :: map() | nil
  defp stringify_keys(nil), do: nil

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      if is_atom(k), do: {Atom.to_string(k), stringify_keys(v)}, else: {k, stringify_keys(v)}
    end)
    |> Enum.into(%{})
  end

  # Walk the list and stringify the keys of
  # of any map members
  defp stringify_keys([head | rest]) do
    [stringify_keys(head) | stringify_keys(rest)]
  end

  defp stringify_keys(not_a_map) do
    not_a_map
  end
end
