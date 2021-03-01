defmodule Glific.Searches.CollectionCountTest do
  use Glific.DataCase

  alias Glific.Searches.CollectionCount

  test "Call collection stats without any data, should return nothing or zero values" do
    result = CollectionCount.collection_stats()
    assert result == %{}

    # the default seed data has only one opted in user
    result = CollectionCount.collection_stats([], false)
    assert result[1] == Map.put(CollectionCount.empty_result(), "Optin", 1)

    result = CollectionCount.collection_stats(["1"], false)
    assert result[1] == Map.put(CollectionCount.empty_result(), "Optin", 1)
  end

  test "Seed data and ensure Unread and other status are valid" do
  end
end
