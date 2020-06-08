defmodule Glific.Communications.ContactBehaviour do
  @doc """
  Invoked when a request runs.

  ## Arguments

  - `payload` - payload for the event
  - `destination` - destination number for communication
  """

  @callback status(args :: Map.t()) ::
              {:ok, response :: Map.t()} | {:error, message :: String.t()}
end
