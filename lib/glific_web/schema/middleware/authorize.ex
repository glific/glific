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
    with current_user <- resolution.context.current_user,
         roles <- get_current_user_roles(current_user),
         true <- is_valid_role?(roles, role, current_user.organization_id) do
      resolution
    else
      _ ->
        resolution
        |> Absinthe.Resolution.put_result({:error, dgettext("errors", "Unauthorized")})
    end
  end

  defp get_current_user_roles(current_user) do
    %{access_roles: access_roles} = Glific.Repo.preload(current_user, [:access_roles])

    access_roles
    |> Enum.reduce([], fn role, role_list -> role_list ++ [role.label] end)
  end

  # Check role with hierarchy
  @spec is_valid_role?(list(), atom() | list(), non_neg_integer()) :: boolean()
  defp is_valid_role?(_, :any, _org_id), do: true
  defp is_valid_role?(roles, :glific_admin, _org_id), do: is_valid_role?(roles, ["Glific Admin"])

  defp is_valid_role?(roles, :admin, _org_id),
    do: is_valid_role?(roles, ["Glific Admin", "Admin"])

  defp is_valid_role?(roles, :manager, org_id),
    do: is_valid_role?(roles, ["Glific Admin", "Admin", "Manager"] ++ organization_roles(org_id))

  defp is_valid_role?(roles, :staff, org_id),
    do:
      is_valid_role?(
        roles,
        ["Glific Admin", "Admin", "Manager", "Staff"] ++ organization_roles(org_id)
      )

  defp is_valid_role?(roles, role) when is_list(role), do: Enum.any?(roles, fn x -> x in role end)

  @spec organization_roles(non_neg_integer()) :: list()
  defp organization_roles(org_id) do
    Glific.AccessControl.organization_roles(%{organization_id: org_id})
  end
end
