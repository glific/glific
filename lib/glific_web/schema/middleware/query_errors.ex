defmodule GlificWeb.Schema.Middleware.QueryErrors do
  @moduledoc """
  Implementing middleware functions to transform errors from Elixir and friends into a format
  consumable and displayable to the API user. This version is specifically for queries.
  """

  @behaviour Absinthe.Middleware

  @doc """
  This is the main middleware callback.

  It receives an %Absinthe.Resolution{} struct and it needs to return an %Absinthe.Resolution{} struct.
  The second argument will be whatever value was passed to the middleware call that setup the middleware.
  """
  @spec call(Absinthe.Resolution.t(), term()) :: Absinthe.Resolution.t()
  def call(res, _) do
    l = Map.get(res, :errors)

    if length(l) == 2 do
      [h | t] = l
      %{res | value: %{errors: [%{key: h, message: t}]}, errors: []}
    end
  end
end
