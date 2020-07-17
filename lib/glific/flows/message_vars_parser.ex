defmodule Glific.Flows.MessageVarParser do
  @moduledoc """
  substitute the contact fileds and result sets in the messages
  """

  @varname [".", "_" | Enum.map(?a..?z, &<<&1>>)]

  @doc """
  parse the message with variables
  """
  @spec parse(String.t(), map()) :: String.t() | nil
  def parse(input, binding) do
    do_parse(input, binding, {nil, ""})
  end

  @spec do_parse(String.t(), map(), {String.t() | nil, String.t()}) :: String.t()
  defp do_parse("", binding, {var, result}) do
    result <> bound(var, binding)
  end

  defp do_parse("@" <> rest, binding, {nil, result}) do
    do_parse(rest, binding, {"", result})
  end

  defp do_parse(<<c::binary-size(1), rest::binary>>, binding, {nil, result}) do
    do_parse(rest, binding, {nil, result <> c})
  end

  defp do_parse(<<c::binary-size(1), rest::binary>>, binding, {var, result}) when c in @varname do
    do_parse(rest, binding, {var <> c, result})
  end

  defp do_parse(<<c::binary-size(1), rest::binary>>, binding, {var, result}) do
    do_parse(rest, binding, {nil, result <> bound(var, binding) <> c})
  end

  @spec bound(String.t(), map()) :: String.t()
  defp bound(nil, _binding), do: ""

  defp bound(var, binding) do
    substitution = get_in(binding, String.split(var, "."))
    if substitution == nil, do: "@#{var}", else: substitution
  end
end
