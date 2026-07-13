defmodule Glific.Flows.Webhooks.CheckResponseTest do
  use Glific.DataCase, async: true

  alias Glific.Flows.Webhooks.Dispatcher

  describe "check_response" do
    test "returns true when the user response matches the correct response" do
      result =
        Dispatcher.dispatch("check_response", %{
          "correct_response" => "yes",
          "user_response" => "yes"
        })

      assert result == %{response: true}
    end

    test "returns false when the user response does not match" do
      result =
        Dispatcher.dispatch("check_response", %{
          "correct_response" => "yes",
          "user_response" => "no"
        })

      assert result == %{response: false}
    end
  end
end
