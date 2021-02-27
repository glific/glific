defmodule Glific.Searches.CollectionCountTest do
  use Glific.DataCase

  alias Glific.Searches.CollectionCount

  test "Call collection stats without any data, should return nothing or zero values" do
    result = CollectionCount.collection_stats()
    assert result == %{}

    result = CollectionCount.collection_stats([], false)
    assert result[1] == Map.put(CollectionCount.empty_result(), "Optin", 1)
  end
end
