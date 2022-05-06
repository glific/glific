defmodule Glific.AccessControlFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Glific.AccessControl` context.
  """

  @doc """
  Generate a role.
  """
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
