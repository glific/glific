defmodule Glific.AI.Tool do
  @moduledoc """
  A single read operation Glific AI may perform against an organisation's data.

  A tool declares what it is called, when it applies and what arguments it takes,
  and implements `run/1`. It never receives a user or an organisation: both come
  from the process state that `Glific.AI.Tools.run/3` establishes before calling
  it, so a tool cannot read outside the caller's tenant even by mistake.

  Adding a capability is a new module plus one line in `Glific.AI.Tools`.
  """

  @doc "Identifier the model uses to call this tool. Stable; changing it is a breaking change."
  @callback name() :: String.t()

  @doc "When to use this tool, written for the model rather than for a developer."
  @callback description() :: String.t()

  @doc "Argument schema, as `NimbleOptions` keyword definitions."
  @callback parameters() :: keyword()

  @doc """
  Performs the read.

  Returns `{:ok, result}` where the result is JSON-encodable, or
  `{:error, message}` where the message explains the problem in terms the model
  can act on — a wrong id or an unknown name is an ordinary outcome here, not a
  failure of the request.
  """
  @callback run(args :: map()) :: {:ok, term()} | {:error, String.t()}
end
