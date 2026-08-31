defmodule Glific.AI.Tool do
  @moduledoc """
  A group of related read operations Glific AI may perform against an
  organisation's data.

  One module per feature area rather than per operation: the flow tools live
  together, the contact tools live together, and a new operation is a clause in
  the module that already owns that area.

  A module declares its operations with `specs/0` and answers them in `run/2`.
  It never receives a user or an organisation: both come from the process state
  that `Glific.AI.Tools.run/3` establishes before calling it, so a tool cannot
  read outside the caller's tenant even by mistake.
  """

  @typedoc """
  One operation, as the model sees it. `parameters` is a `NimbleOptions`
  keyword definition, which is both the argument schema and its documentation.
  """
  @type spec :: %{
          name: String.t(),
          description: String.t(),
          parameters: keyword()
        }

  @doc "Every operation this module answers. Names are stable; changing one is breaking."
  @callback specs() :: [spec()]

  @doc """
  Performs one of the reads named in `specs/0`.

  Returns `{:ok, result}` where the result is JSON-encodable, or
  `{:error, message}` where the message explains the problem in terms the model
  can act on — a wrong id or an unknown name is an ordinary outcome here, not a
  failure of the request.
  """
  @callback run(name :: String.t(), args :: map()) :: {:ok, term()} | {:error, String.t()}
end
