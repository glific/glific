defmodule Glific.Jobs.CollectionWorker do
  @moduledoc """
  Module for checking collection count
  """

  alias Glific.{
    Communications,
    Searches
  }

  @doc """
  periodic function for making calls to collection for collection count
  """
  @spec perform_periodic(non_neg_integer) :: :ok
  def perform_periodic(organization_id) do
    searches = Searches.list_saved_searches(%{filter: %{organization_id: organization_id}})
    searches
    |> Enum.each( fn search ->

      Communications.publish_data(%{key: "Collection_count", value: %{search.id => Searches.saved_search_count(%{id: search.id})}}, :periodic_info, organization_id)
       end)
  end
end
