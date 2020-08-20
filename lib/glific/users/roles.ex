defmodule Glific.EctoRoles do
  @moduledoc """
  Convert and parse the user roles
  """

  use Ecto.Type

  alias Glific.Users.User

  @doc false
  @spec type :: :map
  def type, do: :map

  # Provide custom casting rules.
  @doc """
  Cast the user roles to list
  """
  @spec cast(list()) :: {:ok, list()}
  def cast(data), do: {:ok, data}

  @doc """
    When loading data from the database, as long as it's a list,
    we just put the data into a list of maps to be stored in
    the loaded schema struct.
  """
  @spec load(list()) :: {:ok, list()}
  def load(data) do
    list =
      User.get_roles_list()
      |> Enum.filter(fn role -> role.label in data end)

    {:ok, list}
  end

  @doc """
    When dumping data to the database, we *expect* a list of maps
    but any value could be inserted into the schema struct at runtime,
    so we need to guard against them.
  """
  @spec dump(list()) :: {:ok, list()}
  def dump(roles_map_list) do
    {:ok, roles_map_list}
  end
end
