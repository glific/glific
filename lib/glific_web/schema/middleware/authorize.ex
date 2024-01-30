defmodule GlificWeb.Schema.Middleware.Authorize do
  @moduledoc """
  Implementing middleware functions to transform errors from Ecto Changeset into a format
  consumable and displayable to the API user. This version is specifically for mutations.
  """
  import GlificWeb.Gettext

  @behaviour Absinthe.Middleware

  @doc """
  This is the main middleware callback.

  It receives an %Absinthe.Resolution{} struct and it needs to return an %Absinthe.Resolution{} struct.
  The second argument will be whatever value was passed to the middleware call that setup the middleware.
  """
  @spec call(Absinthe.Resolution.t(), term()) :: Absinthe.Resolution.t()
  def call(resolution, role) do
    with %{roles: roles} <- resolution.context.current_user,
         true <- valid_role?(roles, role) do
      resolution
    else
      _ ->
        resolution
        |> Absinthe.Resolution.put_result({:error, dgettext("errors", "Unauthorized")})
    end
  end

  @doc """
  Check role with hierarchy
  """
  @spec valid_role?(list(), atom() | list()) :: boolean()
  def valid_role?(_, :any), do: true
  def valid_role?(roles, :glific_admin), do: valid_role?(roles, [:glific_admin])
  def valid_role?(roles, :admin), do: valid_role?(roles, [:glific_admin, :admin])

  def valid_role?(roles, :manager),
    do: valid_role?(roles, [:glific_admin, :admin, :manager])

  def valid_role?(roles, role) when role in [:staff, :none],
    do: valid_role?(roles, [:glific_admin, :admin, :manager, :staff])

  def valid_role?(roles, role) when is_list(role), do: Enum.any?(roles, fn x -> x in role end)
  def valid_role?(_, _), do: false
end
