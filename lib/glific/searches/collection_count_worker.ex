defmodule Glific.Jobs.CollectionCountWorker do
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
    Searches.list_saved_searches(%{filter: %{organization_id: organization_id}})
    |> Enum.each(fn saved_search ->
      Communications.publish_data(
        %{
          "Collection_count" => %{
            saved_search.id => Searches.saved_search_count(%{id: saved_search.id})
          }
        },
        :periodic_info,
        organization_id
      )
    end)
  end
end
