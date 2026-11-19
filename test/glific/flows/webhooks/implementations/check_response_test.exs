defmodule Glific.Flows.Webhooks.Implementations.CheckResponseTest do
  use ExUnit.Case, async: true

  alias Glific.Flows.Webhooks.CheckResponse

  @ctx %{organization_id: 1}

  describe "call/2" do
    test "returns response: true when the two texts are equivalent" do
      assert {:ok, %{response: true}} =
               CheckResponse.call(%{"correct_response" => "yes", "user_response" => "yes"}, @ctx)
    end

    test "returns response: false when the two texts differ" do
      assert {:ok, %{response: false}} =
               CheckResponse.call(%{"correct_response" => "yes", "user_response" => "no"}, @ctx)
    end

    test "returns a typed config error (not a crash) when a field is missing" do
      assert {:error, :empty_input, msg} =
               CheckResponse.call(%{"correct_response" => "yes"}, @ctx)

      assert msg =~ "user_response"
    end

    test "returns a typed config error when a field is non-binary" do
      assert {:error, :empty_input, _msg} =
               CheckResponse.call(%{"correct_response" => "yes", "user_response" => nil}, @ctx)
    end
  end
end
