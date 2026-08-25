defmodule Glific.AI.Message do
  @moduledoc """
  Glific's own message format, independent of any provider library.

  This is the boundary that keeps the provider choice replaceable: provider
  structs never leave `Glific.AI.Provider` implementations, and everything above
  that boundary — including what is written to `glific_ai_events` — speaks in
  these structs instead.
  """

  @type role :: :system | :user | :assistant | :tool

  @type t() :: %__MODULE__{
          role: role(),
          content: String.t() | nil,
          tool_call_id: String.t() | nil,
          tool_name: String.t() | nil,
          tool_args: map() | nil
        }

  @enforce_keys [:role]
  defstruct role: nil, content: nil, tool_call_id: nil, tool_name: nil, tool_args: nil

  @doc "A message from the person asking."
  @spec user(String.t()) :: t()
  def user(content), do: %__MODULE__{role: :user, content: content}

  @doc "Standing instructions for the model."
  @spec system(String.t()) :: t()
  def system(content), do: %__MODULE__{role: :system, content: content}

  @doc "A reply from the model."
  @spec assistant(String.t()) :: t()
  def assistant(content), do: %__MODULE__{role: :assistant, content: content}
end
