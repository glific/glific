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
    binding = Glific.stringify_keys(binding)

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


  @doc """
  Interpolates the values from results into the message body. Might need to integrate
  it with the substitution above
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
