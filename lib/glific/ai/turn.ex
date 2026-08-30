defmodule Glific.AI.Turn do
  @moduledoc """
  One turn of a conversation with a model, in Glific's own format.

  Distinct from `Glific.AI.Message`, which is a stored row. A turn is in-memory
  only: it is what goes to the provider and what comes back.

  Provider structs never leave `Glific.AI.Provider` implementations — everything
  above that boundary speaks in these instead, so the client library can be
  replaced without touching callers.
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
