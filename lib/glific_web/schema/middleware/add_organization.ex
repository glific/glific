defmodule GlificWeb.Schema.Middleware.AddOrganization do
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
  def call(resolution, _) do
    case resolution.context do
      %{current_user: current_user} ->
        %{resolution | arguments: put_organization_id(resolution.arguments, current_user)}
      _ ->
        resolution
    end
  end

  def put_organization_id(%{input: _input} = arguments, current_user) do
    put_in(arguments, [:input, :organization_id], current_user.organization_id)
  end

  def put_organization_id(%{filter: _filter} = arguments, current_user) do
    put_in(arguments, [:filter, :organization_id], current_user.organization_id)
  end

  def put_organization_id(arguments, current_user) do
      put_in(arguments,
        [Access.key(:filter, %{}), :organization_id], current_user.organization_id)
  end
end
