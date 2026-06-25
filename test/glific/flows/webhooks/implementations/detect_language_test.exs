defmodule Glific.Flows.Webhooks.DetectLanguageTest do
  @moduledoc """
  Unit tests for the DetectLanguage webhook implementation.

  Tests the module directly via `call/2`, mocking Bhasini.detect_language/1 to
  cover happy path, missing speech field, and API failure scenarios.
  """

  use Glific.DataCase, async: false

  import Mock

  alias Glific.ASR.Bhasini
  alias Glific.Flows.Webhooks.DetectLanguage

  @ctx %{organization_id: 1}

  describe "call/2 - missing speech field" do
    test "returns {:error, 'Missing speech field'} when speech is absent" do
      assert {:error, "Missing speech field"} = DetectLanguage.call(%{}, @ctx)
    end

    test "returns {:error, 'Missing speech field'} when speech is empty string" do
      assert {:error, "Missing speech field"} = DetectLanguage.call(%{"speech" => ""}, @ctx)
    end

    test "returns {:error, 'Missing speech field'} when speech is whitespace only" do
      assert {:error, "Missing speech field"} =
               DetectLanguage.call(%{"speech" => "   "}, @ctx)
    end

    test "returns {:error, 'Missing speech field'} when speech is nil" do
      assert {:error, "Missing speech field"} = DetectLanguage.call(%{"speech" => nil}, @ctx)
    end
  end

  describe "call/2 - happy path" do
    test "returns {:ok, %{detected_language: label}} on successful detection" do
      with_mock(Bhasini, [:passthrough],
        detect_language: fn _url ->
          %{success: true, detected_language: "English"}
        end
      ) do
        fields = %{"speech" => "https://example.com/audio.ogg"}
        assert {:ok, %{detected_language: "English"}} = DetectLanguage.call(fields, @ctx)
      end
    end

    test "passes the speech URL to Bhasini.detect_language/1" do
      test_pid = self()
      url = "https://example.com/voice_note.ogg"

      with_mock(Bhasini, [:passthrough],
        detect_language: fn received_url ->
          send(test_pid, {:called_with, received_url})
          %{success: true, detected_language: "Hindi"}
        end
      ) do
        DetectLanguage.call(%{"speech" => url}, @ctx)
        assert_received {:called_with, ^url}
      end
    end
  end

  describe "call/2 - Bhasini API failure" do
    test "returns {:error, message} when Bhasini detect_language fails" do
      with_mock(Bhasini, [:passthrough],
        detect_language: fn _url ->
          %{success: false, detected_language: "Could not detect language"}
        end
      ) do
        fields = %{"speech" => "https://example.com/audio.ogg"}
        assert {:error, "Could not detect language"} = DetectLanguage.call(fields, @ctx)
      end
    end

    test "returns {:error, message} with the reason from Bhasini" do
      with_mock(Bhasini, [:passthrough],
        detect_language: fn _url ->
          %{success: false, detected_language: "Service unavailable"}
        end
      ) do
        fields = %{"speech" => "https://example.com/audio.ogg"}
        assert {:error, "Service unavailable"} = DetectLanguage.call(fields, @ctx)
      end
    end
  end
end
