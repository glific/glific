defmodule Glific.AI.Telemetry.ContextTest do
  use ExUnit.Case, async: true

  alias Glific.AI.Telemetry.Context

  describe "get/0" do
    test "returns an empty map on a virgin process" do
      assert Context.get() == %{}
    end
  end

  describe "put/1 and get/0" do
    test "round-trips the caller context" do
      context = %{
        organization_id: 1,
        user_id: 2,
        request_id: "req-1",
        skill: "chatbot_diagnose",
        step_index: 3,
        conversation_id: 4
      }

      assert :ok == Context.put(context)
      assert Context.get() == context
    end

    test "keeps only the six known keys" do
      Context.put(%{organization_id: 1, some_other_key: "dropped"})

      assert Context.get() == %{organization_id: 1}
    end

    test "a later put/1 replaces the earlier context rather than merging" do
      Context.put(%{organization_id: 1, user_id: 2})
      Context.put(%{skill: "chatbot_diagnose"})

      assert Context.get() == %{skill: "chatbot_diagnose"}
    end
  end

  describe "clear/0" do
    test "removes the context, restoring the virgin-process default" do
      Context.put(%{organization_id: 1})

      assert :ok == Context.clear()
      assert Context.get() == %{}
    end
  end

  describe "process isolation" do
    test "a context set in a parent is not visible in a Task.async child" do
      Context.put(%{organization_id: 1, skill: "chatbot_diagnose"})

      child_context = Task.async(fn -> Context.get() end) |> Task.await()

      assert child_context == %{}
      assert Context.get() == %{organization_id: 1, skill: "chatbot_diagnose"}
    end
  end
end
