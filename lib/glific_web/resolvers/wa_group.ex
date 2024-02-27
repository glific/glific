defmodule GlificWeb.Resolvers.WaGroup do
  @doc """
  Get the list of contact_groups filtered by args
  """
  @spec contact_wa_groups(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def contact_wa_groups(_, args, _) do
    IO.inspect(Glific.Groups.ContactWaGroups.list_contact_groups(args))
    {:ok, Glific.Groups.ContactWaGroups.list_contact_groups(args)}
  end
end
