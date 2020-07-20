defmodule Glific.Flows.MessageVarParser do
  @moduledoc """
  substitute the contact fileds and result sets in the messages
  """

  @doc """
  parse the message with variables
  """
  @spec parse(String.t(), map()) :: String.t() | nil
  def parse(input, binding) do
    String.replace(input, ~r/@[\w]+[\.][\w]+[\.][\w]*/, &bound(&1, binding))
    |> String.replace(~r/@[\w]+[\.][\w]*/, &bound(&1, binding))
  end

  @spec bound(String.t(), map()) :: String.t()
  defp bound(nil, _binding), do: ""

  # We need to figure out a way to replace these kind of variables
  defp bound("@contact.language", binding) do
    language = get_in(binding, ["contact", "fields", :language])
    language.label
  end

  defp bound(<<_::binary-size(1), var::binary>>, binding) do
    substitution = get_in(binding, String.split(var, "."))
    if substitution == nil, do: "@#{var}", else: substitution
  end
end
