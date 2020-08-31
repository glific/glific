defmodule GlificWeb.Resolvers.Helper do
  @moduledoc """
  Helper funcations for GQL resolvers
  """

  @doc """
   Will use this helper funcation to add the organization in into the
   filters for all the list and count funcations
  """
  @spec add_org_filter(map(), map()) :: map()
  def add_org_filter(args, %{context: %{current_user: current_user}}) do
    put_in(args, [Access.key(:filter, %{}), :organization_id], current_user.organization_id)
  end
end
