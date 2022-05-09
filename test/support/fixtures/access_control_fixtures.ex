defmodule Glific.AccessControlFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Glific.AccessControl` context.
  """

  alias Glific.{
    AccessControl.Permission,
    AccessControl.Role
  }

  @doc """
  Generate a role.
  """
  @spec role_fixture(map()) :: Role.t()
  def role_fixture(attrs \\ %{}) do
    {:ok, role} =
      attrs
      |> Enum.into(%{
        description: "some description",
        is_reserved: true,
        label: "some label"
      })
      |> Glific.AccessControl.create_role()

    role
  end

  @doc """
  Generate a permission.
  """
  @spec permission_fixture(map()) :: Permission.t()
  def permission_fixture(attrs \\ %{}) do
    {:ok, permission} =
      attrs
      |> Enum.into(%{
        entity: "some entity"
      })
      |> Glific.AccessControl.create_permission()

    permission
  end
end
