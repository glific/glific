defmodule Glific.Flows.ValueText do
  @moduledoc """
  Renders a flow value as the text an author sees.

  Flow expressions and `@variable` substitution both have to turn an arbitrary term
  into a string: a router operand becomes a message body, a contact field becomes a
  stored value, `@results.foo` becomes part of a message.

  `to_string/1` alone is not enough for that job. It raises for a map (no
  `String.Chars` implementation), and — worse — it silently treats `[1, 2, 3]` as a
  charlist and `["a", "b"]` as `"ab"`. Structured values therefore render here:
  maps as JSON, lists as a comma-separated join of their rendered elements.

  A term JSON cannot represent (a tuple, a pid) raises rather than rendering. That
  is deliberate: in `Glific.Flows.Expression` the raise is contained by `isolated/1`
  and degrades to "Invalid Code", which tells the author their expression is wrong.
  Emitting `inspect/1` output into a beneficiary's message instead would leak
  internals and hide the mistake.
  """

  @doc "Render a flow value as author-facing text."
  @spec to_text(any()) :: String.t()
  def to_text(value) when is_binary(value), do: value

  def to_text(value) when is_struct(value), do: to_string(value)

  def to_text(value) when is_map(value), do: Jason.encode!(value)

  def to_text(value) when is_list(value), do: Enum.map_join(value, ", ", &to_text/1)

  def to_text(value), do: to_string(value)
end
