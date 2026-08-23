defmodule Glific.AI.ModelTest do
  use ExUnit.Case, async: false

  alias Glific.AI.Model
  alias Glific.AI.Model.Result
  alias Glific.AI.Model.Stub
  alias ReqLLM.Context

  setup do
    start_supervised!(Stub)
    :ok
  end

  describe "chat/2 — delegates to the configured adapter" do
    test "config/test.exs points :ai_model_adapter at the Stub" do
      assert Application.get_env(:glific, :ai_model_adapter) == Stub
    end

    test "chat/2 goes through whatever config :ai_model_adapter names" do
      Stub.queue_text("delegated")

      assert {:ok, %Result{message: %{content: [%{text: "delegated"}]}}} =
               Model.chat(Context.new([Context.user("hi")]), [])
    end

    test "object/3 goes through whatever config :ai_model_adapter names" do
      Stub.queue_object(%{"answer" => "42"})

      assert {:ok, %{"answer" => "42"}} =
               Model.object(Context.new([Context.user("hi")]), [answer: [type: :string]], [])
    end
  end

  describe "adapter selection" do
    test "falls back to Glific.AI.Model.ReqLLM when unconfigured" do
      original = Application.get_env(:glific, :ai_model_adapter)
      Application.delete_env(:glific, :ai_model_adapter)

      on_exit(fn -> Application.put_env(:glific, :ai_model_adapter, original) end)

      assert {:error, message} =
               Model.chat(Context.new([Context.user("hi")]),
                 model: "not_a_real_provider:xyz",
                 api_key: "sk-test"
               )

      assert is_binary(message)
    end
  end
end
