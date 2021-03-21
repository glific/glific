defmodule Glific.Searches.CollectionCount do
  @moduledoc """
  Module for checking collection count
  """

  import Ecto.Query, warn: false

  use Publicist

  alias Glific.{
    Communications,
    Contacts.Contact,
    Partners,
    Repo
  }

  @spec org_id_list(list(), boolean) :: list()
  defp org_id_list([], recent) do
    Partners.active_organizations([])
    |> Partners.recent_organizations(recent)
    |> Enum.reduce([], fn {id, _map}, acc -> [id | acc] end)
  end

  defp org_id_list(list, _recent) do
    Enum.map(
      list,
      fn l ->
        {:ok, int_l} = Glific.parse_maybe_integer(l)
        int_l
      end
    )
  end

  @spec publish_data(map()) :: map()
  defp publish_data(results) do
    results
    |> Enum.map(fn {id, stats} ->
      Communications.publish_data(
        %{"collection" => stats},
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
  @spec collection_stats(list, boolean) :: map()
  def collection_stats(list \\ [], recent \\ true) do
    org_id_list = org_id_list(list, recent)

    # org_id_list can be empty here, if so we return an empty map
    if org_id_list == [],
      do: %{},
      else: do_collection_stats(org_id_list)
  end

  @spec do_collection_stats(list()) :: map()
  defp do_collection_stats(org_id_list) do
    query = query(org_id_list)

    org_id_list
    # create the empty results array for each org in list
    |> empty_results()
    |> all(query)
    |> unread(query)
    |> not_replied(query)
    |> not_responded(query)
    |> optin(query)
    |> optout(query)
    |> publish_data()
  end

  @spec empty_results(list()) :: map()
  defp empty_results(org_id_list),
    do:
      Enum.reduce(
        org_id_list,
        %{},
        fn id, acc -> Map.put(acc, id, empty_result()) end
      )

  @spec empty_result :: map()
  defp empty_result,
    do: %{
      "All" => 0,
      "Not replied" => 0,
      "Not Responded" => 0,
      "Optin" => 0,
      "Optout" => 0,
      "Unread" => 0
    }

  @spec add(map(), non_neg_integer, String.t(), non_neg_integer) :: map()
  defp add(result, org_id, key, value) do
    result
    |> Map.put(org_id, Map.put(result[org_id], key, value))
  end

  @spec add_orgs(Ecto.Query.t(), list()) :: Ecto.Query.t()
  defp add_orgs(query, org_id_list) do
    query
    |> where([o], o.organization_id in ^org_id_list)
  end

  @spec query(list()) :: Ecto.Query.t()
  defp query(org_id_list) do
    Contact
    # block messages sent to group
    |> where([c], c.status != :blocked)
    |> add_orgs(org_id_list)
    |> group_by([c], c.organization_id)
    |> select([c], [count(c.id), c.organization_id])
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
    |> where([c], c.last_message_number > 0)
    |> make_result(result, "All")
  end

  @spec unread(map(), Ecto.Query.t()) :: map()
  defp unread(result, query) do
    query
    |> where([c], c.last_message_number > 0)
    |> where([c], c.is_org_read == false)
    |> make_result(result, "Unread")
  end

  @spec not_replied(map(), Ecto.Query.t()) :: map()
  defp not_replied(result, query) do
    query
    |> where([c], c.last_message_number > 0)
    |> where([c], c.is_org_replied == false)
    |> make_result(result, "Not replied")
  end

  @spec not_responded(map(), Ecto.Query.t()) :: map()
  defp not_responded(result, query) do
    query
    |> where([c], c.last_message_number > 0)
    |> where([c], c.is_contact_replied == false)
    |> make_result(result, "Not Responded")
  end

  @spec optin(map(), Ecto.Query.t()) :: map()
  defp optin(result, query) do
    query
    |> where([c], c.optin_status == true)
    |> make_result(result, "Optin")
  end

  @spec optout(map(), Ecto.Query.t()) :: map()
  defp optout(result, query) do
    query
    |> where([c], not is_nil(c.optout_time))
    |> make_result(result, "Optout")
  end
end
