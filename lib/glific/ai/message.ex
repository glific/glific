defmodule Glific.AI.Message do
  @moduledoc """
  Glific's own message format, independent of any provider library.

  This is the boundary that keeps the provider choice replaceable: provider
  structs never leave `Glific.AI.Provider` implementations, and everything above
  that boundary — including what is written to `glific_ai_events` — speaks in
  these structs instead.
  """

  @type role :: :system | :user | :assistant | :tool

  @typedoc """
  A tool the model asked us to run. `id` is the provider's identifier for the
  call, and pairing the eventual result back to it is what lets a conversation
  be replayed faithfully.
  """
  @type tool_call :: %{id: String.t(), name: String.t(), args: map()}

  @type t() :: %__MODULE__{
          role: role(),
          content: String.t() | nil,
          tool_calls: [tool_call()],
          tool_call_id: String.t() | nil,
          tool_name: String.t() | nil
        }

  @enforce_keys [:role]
  defstruct role: nil, content: nil, tool_calls: [], tool_call_id: nil, tool_name: nil

  @doc "A message from the person asking."
  @spec user(String.t()) :: t()
  def user(content), do: %__MODULE__{role: :user, content: content}

  @doc "Standing instructions for the model."
  @spec system(String.t()) :: t()
  def system(content), do: %__MODULE__{role: :system, content: content}

  @doc "A reply from the model, which may ask for tools to be run."
  @spec assistant(String.t() | nil, [tool_call()]) :: t()
  def assistant(content, tool_calls \\ []),
    do: %__MODULE__{role: :assistant, content: content, tool_calls: tool_calls}

  @doc """
  The outcome of running one tool, addressed back to the call that asked for it.
  """
  @spec tool_result(String.t(), String.t(), String.t()) :: t()
  def tool_result(tool_call_id, tool_name, content) do
    %__MODULE__{
      role: :tool,
      tool_call_id: tool_call_id,
      tool_name: tool_name,
      content: content
    }
  end

  @doc "Whether the model is asking for tools rather than answering."
  @spec tool_calls?(t()) :: boolean()
  def tool_calls?(%__MODULE__{tool_calls: calls}), do: calls != []
end
