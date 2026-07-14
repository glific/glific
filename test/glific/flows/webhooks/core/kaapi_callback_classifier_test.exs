defmodule Glific.Flows.Webhooks.Core.KaapiCallbackClassifierTest do
  use ExUnit.Case, async: true

  alias Glific.Flows.Webhooks.{ErrorType, KaapiCallbackClassifier}

  describe "classify/1" do
    test "a nested http_status 4xx (except 408/429) is a config error" do
      assert KaapiCallbackClassifier.classify(%{"http_status" => 400}) == :invalid_input
      assert KaapiCallbackClassifier.classify(%{"http_status" => 404}) == :invalid_input
      assert ErrorType.class(:invalid_input) == :config
    end

    test "a 4xx code parsed from the reason string is a config error" do
      result = %{"reason" => "OpenAI bad request (code: 400): Invalid 'conversation.id'"}
      assert KaapiCallbackClassifier.classify(result) == :invalid_input
    end

    test "a Status: NNN code embedded in the reason is honoured too" do
      assert KaapiCallbackClassifier.classify(%{"reason" => "denied. Status: 403"}) ==
               :invalid_input
    end

    test "a nested http_status 5xx is a system error" do
      assert KaapiCallbackClassifier.classify(%{"http_status" => 500}) == :unknown
      assert KaapiCallbackClassifier.classify(%{"http_status" => 502}) == :unknown
      assert ErrorType.class(:unknown) == :system
    end

    test "a 5xx code parsed from the reason string is a system error" do
      result = %{"reason" => "[GEMINI] Server error (code: 500 INTERNAL): upstream failed"}
      assert KaapiCallbackClassifier.classify(result) == :unknown
    end

    test "408 / 429 are upstream blips → system (we do not retry)" do
      assert KaapiCallbackClassifier.classify(%{"http_status" => 408}) == :rate_limited
      assert KaapiCallbackClassifier.classify(%{"http_status" => 429}) == :rate_limited
      assert ErrorType.class(:rate_limited) == :system
    end

    test "a crash signature is unjudgeable → system, even without a status" do
      result = %{"reason" => "no function clause matching in Kaapi.parse/1"}
      assert KaapiCallbackClassifier.classify(result) == :unknown
    end

    test "an overloaded / locked upstream is a system error (before any status rule)" do
      # code 400 present, but the transient signature wins so it is NOT misfiled as config.
      locked = %{"reason" => "OpenAI bad request (code: 400): conversation_locked"}
      assert KaapiCallbackClassifier.classify(locked) == :service_unavailable

      overloaded = %{"reason" => "The server is overloaded, please try again"}
      assert KaapiCallbackClassifier.classify(overloaded) == :service_unavailable
      assert ErrorType.class(:service_unavailable) == :system
    end

    test "the error key is used when reason is absent" do
      assert KaapiCallbackClassifier.classify(%{"error" => "denied (code: 401)"}) ==
               :invalid_input
    end

    test "an atom :reason key is read (not only the string key)" do
      assert KaapiCallbackClassifier.classify(%{reason: "denied. Status: 403"}) == :invalid_input
    end

    test "a string http_status is normalised (4xx stays config)" do
      assert KaapiCallbackClassifier.classify(%{"http_status" => "404"}) == :invalid_input
    end

    test "a 4xx reason containing 'try again' stays config (not misfiled as overload)" do
      result = %{"http_status" => 400, "reason" => "bad input, please try again"}
      assert KaapiCallbackClassifier.classify(result) == :invalid_input
    end

    test "a statusless, unrecognised reason fails safe to system" do
      result = %{"reason" => "[GEMINI] STT response is missing transcribed text"}
      assert KaapiCallbackClassifier.classify(result) == :unknown
    end

    test "a non-binary reason does not crash the classifier and fails safe to system" do
      assert KaapiCallbackClassifier.classify(%{"reason" => %{nested: "map"}}) == :unknown
      assert KaapiCallbackClassifier.classify(%{}) == :unknown
      assert KaapiCallbackClassifier.classify(nil) == :unknown
    end

    test "a nested http_status wins over a code embedded in the reason" do
      result = %{"http_status" => 503, "reason" => "wrapped (code: 400)"}
      assert KaapiCallbackClassifier.classify(result) == :unknown
    end
  end
end
