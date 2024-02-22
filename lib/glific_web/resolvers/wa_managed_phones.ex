defmodule GlificWeb.Resolvers.WAManagedPhones do
  @moduledoc """
  WAManagedPhone Resolver which sits between the GraphQL schema and Glific WAManagedPhone Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{
    WAManagedPhones,
    WAGroup.WAManagedPhone
  }

  @doc """
  Get the list of wa_managed_phones filtered by args
  """
  @spec wa_managed_phones(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, [WAManagedPhone]}
  def wa_managed_phones(_, args, _) do
    {:ok, WAManagedPhones.list_wa_managed_phones(args)}
  end

  @doc """
  Get the count of wa_managed_phones filtered by args
  """
  @spec count_wa_managed_phones(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, integer}
  def count_wa_managed_phones(_, args, _) do
    {:ok, WAManagedPhones.count_wa_managed_phones(args)}
  end
end
