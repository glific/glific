defmodule Glific.Flows.Webhooks.SpeechToTextWithBhasiniTest do
  @moduledoc """
  Unit tests for the SpeechToTextWithBhasini webhook implementation.

  Tests the module directly via `call/2`, mocking Bhasini.validate_params/1
  and Gemini.speech_to_text/2 to cover happy path, missing fields, and API
  failure scenarios.
  """

  use Glific.DataCase, async: false

  import Mock

  alias Glific.ASR.Bhasini
  alias Glific.Contacts.Contact
  alias Glific.Flows.Webhooks.SpeechToTextWithBhasini
  alias Glific.ThirdParty.Gemini

  @ctx %{organization_id: 1}

  @valid_fields %{
    "speech" => "https://example.com/audio.ogg",
    "contact" => %{"id" => "1"}
  }

  @mock_contact %Contact{id: 1, organization_id: 1}

  describe "call/2 - happy path" do
    test "returns {:ok, map} with asr_response_text on Gemini success" do
      with_mocks([
        {Bhasini, [:passthrough], [validate_params: fn _fields -> {:ok, @mock_contact} end]},
        {Gemini, [:passthrough],
         [
           speech_to_text: fn _url, _org_id ->
             %{success: true, asr_response_text: "transcribed text"}
           end
         ]}
      ]) do
        assert {:ok, result} = SpeechToTextWithBhasini.call(@valid_fields, @ctx)
        assert result.asr_response_text == "transcribed text"
        refute Map.has_key?(result, :success)
      end
    end

    test "strips the :success key from the success result map" do
      with_mocks([
        {Bhasini, [:passthrough], [validate_params: fn _fields -> {:ok, @mock_contact} end]},
        {Gemini, [:passthrough],
         [
           speech_to_text: fn _url, _org_id ->
             %{success: true, asr_response_text: "hello", extra_key: "extra"}
           end
         ]}
      ]) do
        assert {:ok, result} = SpeechToTextWithBhasini.call(@valid_fields, @ctx)
        refute Map.has_key?(result, :success)
        assert result.extra_key == "extra"
      end
    end
  end

  describe "call/2 - missing or invalid fields" do
    test "returns {:error, message} when Bhasini.validate_params/1 fails" do
      with_mock(Bhasini, [:passthrough],
        validate_params: fn _fields ->
          {:error, "Missing required parameters: contact or speech"}
        end
      ) do
        assert {:error, msg} = SpeechToTextWithBhasini.call(%{}, @ctx)
        assert is_binary(msg)
        assert msg =~ "Missing"
      end
    end

    test "returns {:error, message} for invalid media URL" do
      with_mock(Bhasini, [:passthrough],
        validate_params: fn _fields -> {:error, "Media URL is invalid"} end
      ) do
        fields = Map.put(@valid_fields, "speech", "http://not-https.com/audio.ogg")
        assert {:error, "Media URL is invalid"} = SpeechToTextWithBhasini.call(fields, @ctx)
      end
    end
  end

  describe "call/2 - Gemini API failure" do
    test "returns {:error, message} when Gemini returns success: false with asr_response_text" do
      with_mocks([
        {Bhasini, [:passthrough], [validate_params: fn _fields -> {:ok, @mock_contact} end]},
        {Gemini, [:passthrough],
         [
           speech_to_text: fn _url, _org_id ->
             %{success: false, asr_response_text: "Gemini STT failed upstream"}
           end
         ]}
      ]) do
        assert {:error, msg} = SpeechToTextWithBhasini.call(@valid_fields, @ctx)
        assert msg == "Gemini STT failed upstream"
      end
    end

  end
end
