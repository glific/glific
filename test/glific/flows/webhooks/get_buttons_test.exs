defmodule Glific.Flows.Webhooks.GetButtonsTest do
  use Glific.DataCase, async: true

  alias Glific.Flows.Webhooks.Dispatcher

  describe "get_buttons" do
    test "splits a |-delimited string into numbered buttons, trimming whitespace" do
      result = Dispatcher.dispatch("get_buttons", %{"buttons_data" => "Yes | No | Maybe"})

      assert result == %{
               buttons: %{"button_1" => "Yes", "button_2" => "No", "button_3" => "Maybe"},
               button_count: 3,
               is_valid: true
             }
    end

    test "handles a single button" do
      result = Dispatcher.dispatch("get_buttons", %{"buttons_data" => "  Only  "})

      assert result == %{buttons: %{"button_1" => "Only"}, button_count: 1, is_valid: true}
    end
  end
end
