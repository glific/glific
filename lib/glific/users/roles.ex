defmodule Glific.EctoRoles do
  @moduledoc """
  Convert and parse the user roles
  """

  use Ecto.Type

  alias Glific.Users.User

  def type, do: :map

  # Provide custom casting rules.
  def cast(data) when is_list(data), do: {:ok, data}

  # When loading data from the database, as long as it's a list,
  # we just put the data into a list of maps to be stored in
  # the loaded schema struct.
  def load(data) when is_list(data) do
    list =
      User.get_roles_list()
      |> Enum.filter(fn role -> role.label in data end)

    {:ok, list}
  end

  # When dumping data to the database, we *expect* a list of maps
  # but any value could be inserted into the schema struct at runtime,
  # so we need to guard against them.
  def dump(roles_map_list) when is_list(roles_map_list) do
    {:ok, roles_map_list}
  end

  def dump(_), do: :error
end
