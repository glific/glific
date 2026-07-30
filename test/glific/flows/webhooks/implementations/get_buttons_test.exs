defmodule Glific.Flows.Webhooks.Implementations.GetButtonsTest do
  use ExUnit.Case, async: true

  alias Glific.Flows.Webhooks.GetButtons

  @ctx %{organization_id: 1}

  describe "call/2" do
    test "splits a |-delimited string into numbered buttons" do
      assert {:ok, result} = GetButtons.call(%{"buttons_data" => "A|B|C"}, @ctx)
      assert result.button_count == 3
      assert result.buttons == %{"button_1" => "A", "button_2" => "B", "button_3" => "C"}
      assert result.is_valid == true
    end

    test "returns a typed config error (not a crash) when buttons_data is missing" do
      assert {:error, :empty_input, msg} = GetButtons.call(%{}, @ctx)
      assert msg =~ "buttons_data"
    end

    test "returns a typed config error when buttons_data is non-binary" do
      assert {:error, :empty_input, _msg} = GetButtons.call(%{"buttons_data" => nil}, @ctx)
    end
  end
end
