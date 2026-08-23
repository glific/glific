defmodule Glific.AI.Tool.ContextTest do
  use ExUnit.Case, async: true

  alias Glific.AI.Tool.Context
  alias Glific.Users.User

  test "struct carries the acting identity and run position" do
    context = %Context{
      organization_id: 1,
      user: %User{id: 42},
      request_id: "req-123",
      step_index: 2
    }

    assert context.organization_id == 1
    assert %User{id: 42} = context.user
    assert context.request_id == "req-123"
    assert context.step_index == 2
  end

  test "every field is enforced at struct-build time" do
    assert_raise ArgumentError, fn ->
      Code.eval_string("%Glific.AI.Tool.Context{organization_id: 1}")
    end
  end
end
