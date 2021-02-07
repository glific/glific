defmodule Glific.Jobs.CollectionCountWorker do
  @moduledoc """
  Module for checking collection count
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Communications,
    Contacts.Contact,
    Messages.Message,
    Partners,
    Repo,
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
          key: "Collection_count",
          value: %{saved_search.id => Searches.saved_search_count(%{id: saved_search.id})}
        },
        :periodic_info,
        organization_id
      )
    end)
  end

  @doc """
  Do it in one query for all organizations for each of Unread, Not Responded, Not Replied and OptOut
  """
  @spec collection_stats :: map()
  def collection_stats do
    org_id_list =
      Partners.active_organizations([])
      |> Partners.recent_organizations(true)
      |> Enum.reduce([], fn {id, _map}, acc -> [id | acc] end)

    query = query(org_id_list)

    %{}
    |> unread(query)
    |> not_replied(query)
    |> not_responded(query)
    |> optout(org_id_list)
    |> Enum.map(fn {id, stats} ->
      Communications.publish_data(
        %{"Collection_count" => stats},
        :collection_count,
        id
      )

      {id, stats}
    end)
    |> Enum.into(%{})
  end

  @spec empty_result :: map()
  defp empty_result,
    do: %{
      "Unread" => 0,
      "Not replied" => 0,
      "Not Responded" => 0,
      "Optout" => 0
    }

  @spec add(map(), non_neg_integer, String.t(), non_neg_integer) :: map()
  defp add(result, org_id, key, value) do
    org_values =
      if Map.has_key?(result, org_id),
        do: result[org_id],
        else: empty_result()

    Map.put(result, org_id, Map.put(org_values, key, value))
  end

  @spec query(list()) :: Ecto.Query.t()
  defp query(org_id_list) do
    Message
    |> join(:inner, [m], c in Contact, on: m.contact_id == c.id)
    |> where([m, _c], m.organization_id in ^org_id_list)
    |> where([_m, c], c.status != :blocked)
    |> group_by([m, _c], m.organization_id)
    |> select([m, _c], [count(m.id), m.organization_id])
  end

  @spec make_result(Ecto.Query.t(), map(), String.t()) :: map()
  defp make_result(query, result, key) do
    query
    |> Repo.all(skip_organization_id: true)
    |> Enum.reduce(
      result,
      fn [cnt, org_id], result -> add(result, org_id, key, cnt) end
    )
  end

  @spec unread(map(), Ecto.Query.t()) :: map()
  defp unread(result, query) do
    query
    |> where([m], m.is_read == false)
    |> where([m], m.flow == :inbound)
    |> make_result(result, "Unread")
  end

  @spec not_replied(map(), Ecto.Query.t()) :: map()
  defp not_replied(result, query) do
    query
    |> where([m], m.is_replied == false)
    |> where([m], m.flow == :inbound)
    |> make_result(result, "Not replied")
  end

  @spec not_responded(map(), Ecto.Query.t()) :: map()
  defp not_responded(result, query) do
    query
    |> where([m], m.is_replied == false)
    |> where([m], m.flow == :outbound)
    |> make_result(result, "Not Responded")
  end

  @spec optout(map(), list()) :: map()
  defp optout(result, org_id_list) do
    Contact
    |> where([c], c.status != :blocked)
    |> where([c], c.organization_id in ^org_id_list)
    |> where([c], not is_nil(c.optout_time))
    |> group_by([c], c.organization_id)
    |> select([c], [count(c.id), c.organization_id])
    |> make_result(result, "Optout")
  end
end
