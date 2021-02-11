defmodule Glific.Searches.CollectionCount do
  @moduledoc """
  Module for checking collection count
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Communications,
    Contacts.Contact,
    Messages.Message,
    Partners,
    Repo
  }

  @spec org_id_list :: list()
  defp org_id_list do
    Partners.active_organizations([])
    |> Partners.recent_organizations(recent)
    |> Enum.reduce([], fn {id, _map}, acc -> [id | acc] end)
  end

  @spec publish_data(list()) :: map()
  defp publish_data(results) do
    results
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

  @doc """
  Do it in one query for all organizations for each of Unread, Not Responded, Not Replied and OptOut
  """
  @spec collection_stats(boolean) :: map()
  def collection_stats(recent \\ true) do
    org_id_list = org_id_list()

    query = query(org_id_list)

    %{}
    |> all(query)
    |> unread(query)
    |> not_replied(query)
    |> not_responded(query)
    |> optout(org_id_list)
    |> publish_data()
  end

  @spec empty_result :: map()
  defp empty_result,
    do: %{
      "All" => 0,
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

  @spec add_orgs(Ecto.Query.t(), list()) :: Ecto.Query.t()
  defp add_orgs(query, []), do: query

  defp add_orgs(query, org_id_list) do
    query
    |> where([m], m.organization_id in ^org_id_list)
  end

  @spec query(list()) :: Ecto.Query.t()
  defp query(org_id_list) do
    Message
    |> join(:inner, [m], c in Contact, on: m.contact_id == c.id)
    |> add_orgs(org_id_list)
    # block messages sent to group
    |> where([m, c], c.status != :blocked and m.receiver_id != m.sender_id)
    |> group_by([_m, c], c.organization_id)
    |> select([_m, c], [count(c.id, :distinct), c.organization_id])
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

  @spec all(map(), Ecto.Query.t()) :: map()
  defp all(result, query) do
    query
    |> make_result(result, "All")
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
    |> where([c], c.status != :blocked and not is_nil(c.optout_time))
    |> add_orgs(org_id_list)
    |> group_by([c], c.organization_id)
    |> select([c], [count(c.id), c.organization_id])
    |> make_result(result, "Optout")
  end
end
