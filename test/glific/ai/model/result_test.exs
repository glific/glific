defmodule Glific.AI.Model.ResultTest do
  use ExUnit.Case, async: true

  alias Glific.AI.Model.Result

  describe "zero_usage/0" do
    test "returns an all-zero usage map with the four canonical keys" do
      assert Result.zero_usage() == %{prompt: 0, completion: 0, cached: 0, cache_creation: 0}
    end
  end
end
