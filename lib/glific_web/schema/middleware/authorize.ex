defmodule GlificWeb.Schema.Middleware.Authorize do
  @moduledoc """
  Implementing middleware functions to transform errors from Ecto Changeset into a format
  consumable and displayable to the API user. This version is specifically for mutations.
  """

  @behaviour Absinthe.Middleware

  @doc """
  This is the main middleware callback.

  It receives an %Absinthe.Resolution{} struct and it needs to return an %Absinthe.Resolution{} struct.
  The second argument will be whatever value was passed to the middleware call that setup the middleware.
  """
  @spec call(Absinthe.Resolution.t(), term()) :: Absinthe.Resolution.t()
  def call(resolution, role) do
    # IO.inspect("resolution <> resolution")
    # IO.inspect(Absinthe.Resolution.path(resolution))
    # IO.inspect(Absinthe.Resolution.path_string(resolution))
    # IO.inspect(resolution.source)
    with %{current_user: current_user} <- resolution.context,
      true <- is_valid_role?(current_user, role) do
        resolution
    else
      _ -> resolution
          |> Absinthe.Resolution.put_result({:error, "Unauthorized"})
    end
  end


  defp is_valid_role?(_, :any), do: true
  defp is_valid_role?(current_user, role) do
    # IO.inspect(current_user)
    role in current_user.roles
  end

end
