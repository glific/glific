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
    with %{roles: roles} <- resolution.context.current_user,
         true <- is_valid_role?(roles, role) do
      resolution
    else
      _ ->
        resolution
        |> Absinthe.Resolution.put_result({:error, "Unauthorized"})
    end
  end

  # Check role with hierarchy
  @spec is_valid_role?(list(), atom() | list()) :: boolean()
  defp is_valid_role?(_, :any), do: true
  defp is_valid_role?(roles, :admin), do: is_valid_role?(roles, [:admin])
  defp is_valid_role?(roles, :manager), do: is_valid_role?(roles, [:admin, :manager])
  defp is_valid_role?(roles, :staff), do: is_valid_role?(roles, [:admin, :manager, :staff])

  defp is_valid_role?(roles, role) when is_list(role), do: Enum.any?(roles, fn x -> x in role end)
  defp is_valid_role?(_, _), do: false
end
