defmodule Glific.Flows.Webhooks.Core.ErrorClassifierTest do
  use ExUnit.Case, async: true

  alias Glific.Flows.Webhooks.ErrorClassifier

  # A fake webhook module that classifies its own domain failures.
  defmodule StubModule do
    def error_class(%{reason: "known config" <> _}), do: :config
    def error_class(%{reason: "kaapi not active" <> _}), do: :system
    def error_class(_result), do: nil
  end

  describe "classify/2 — module verdict first" do
    test "uses the module's error_class when it returns a class" do
      assert ErrorClassifier.classify(StubModule, %{reason: "known config error"}) == :config

      assert ErrorClassifier.classify(StubModule, %{reason: "kaapi not active for org"}) ==
               :system
    end

    test "module verdict overrides a conflicting provider status" do
      assert ErrorClassifier.classify(StubModule, %{
               reason: "known config error",
               http_status: 500
             }) ==
               :config
    end

    test "defers to the heuristic when the module returns nil" do
      assert ErrorClassifier.classify(StubModule, %{reason: "opaque", http_status: 502}) ==
               :system
    end

    test "nil module falls straight to the heuristic" do
      assert ErrorClassifier.classify(nil, %{http_status: 400}) == :config
    end
  end

  describe "heuristic/1 — engine tiers" do
    test "crash signature → system (even though logged as 400)" do
      assert ErrorClassifier.heuristic(%{
               reason: "GCSWORKER: upload failed — no function clause matching in ..."
             }) == :system
    end

    test "conversation_locked (a 400) → transient, not config" do
      assert ErrorClassifier.heuristic(%{
               reason: "OpenAI bad request (code: 400): ... 'code': 'conversation_locked' ..."
             }) == :transient
    end

    test "a Google 'rate limit exceeded' → transient" do
      assert ErrorClassifier.heuristic(%{
               reason: "Failed to copy slide. Status: 403, rate limit exceeded"
             }) ==
               :transient
    end

    test "nested http_status 502 → system" do
      assert ErrorClassifier.heuristic(%{http_status: 502}) == :system
    end

    test "408 / 429 → transient" do
      assert ErrorClassifier.heuristic(%{http_status: 408}) == :transient
      assert ErrorClassifier.heuristic(%{http_status: 429}) == :transient
    end

    test "a 4xx code parsed from the message → config" do
      assert ErrorClassifier.heuristic(%{
               message: "OpenAI bad request (code: 400): Invalid 'conversation.id' ..."
             }) == :config
    end

    test "a 5xx code parsed from the message → system" do
      assert ErrorClassifier.heuristic(%{
               message: "[GEMINI] Server error (code: 500 INTERNAL): ..."
             }) ==
               :system
    end

    test "unknown statusless error → system (fail safe)" do
      assert ErrorClassifier.heuristic(%{
               reason: "[GEMINI] STT response is missing transcribed text"
             }) ==
               :system

      assert ErrorClassifier.heuristic(%{}) == :system
    end
  end

  describe "route/1" do
    test "maps each class to its action" do
      assert ErrorClassifier.route(:system) == {:report, "flow_webhooks"}
      assert ErrorClassifier.route(:config) == {:report, "flow_webhook_config_errors"}
      assert ErrorClassifier.route(:transient) == :count
      assert ErrorClassifier.route(:stale) == :suppress
    end
  end
end
