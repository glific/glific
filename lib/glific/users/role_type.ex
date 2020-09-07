defmodule Glific.Users.RoleType do
  use Ecto.Type
  def type, do: {:array, Glific.Enums.UserRoles}

  # Provide custom casting rules.
  # Cast strings into the URI struct to be used at runtime
  def cast(uri), do: {:ok, uri}

  # # Accept casting of URI structs as well
  # def cast(%URI{} = uri), do: {:ok, uri}

  # # Everything else is a failure though
  # def cast(_), do: :error

  # When loading data from the database, as long as it's a map,
  # we just put the data back into an URI struct to be stored in
  # the loaded schema struct.
  def load(data), do: {:ok, data}

  # When dumping data to the database, we *expect* an URI struct
  # but any value could be inserted into the schema struct at runtime,
  # so we need to guard against them.
  def dump(data), do: {:ok, data}
  def dump(_), do: :error
end
