defmodule Glific.Flows.Webhooks.Core.SmokeTestTest do
  use Glific.DataCase, async: false

  import ExUnit.CaptureIO
  import Mock

  alias Glific.Fixtures

  alias Glific.Flows.Webhook
  alias Glific.Flows.Webhooks.Core.SmokeTest

  alias Glific.Flows.Webhooks.{
    FilesearchGpt,
    Geolocation,
    Kaapi,
    SpeechToText,
    TextToSpeech,
    VoiceFilesearchGpt
  }

  @nodes [
    "geolocation",
    "speech_to_text",
    "text_to_speech",
    "filesearch-gpt",
    "voice-filesearch-gpt"
  ]

  # Each entry stubs a module's call/2 with the given result.
  defp mock_calls(results) do
    [
      {Geolocation, [], [call: fn _fields, _ctx -> results.geolocation end]},
      {SpeechToText, [], [call: fn _fields, _ctx -> results.speech_to_text end]},
      {TextToSpeech, [], [call: fn _fields, _ctx -> results.text_to_speech end]},
      {FilesearchGpt, [], [call: fn _fields, _ctx -> results.filesearch end]},
      {VoiceFilesearchGpt, [], [call: fn _fields, _ctx -> results.voice_filesearch end]}
    ]
  end

  @all_ok %{
    geolocation: {:ok, %{city: "Bengaluru"}},
    speech_to_text: {:ok, %{success: true}},
    text_to_speech: {:ok, %{success: true}},
    filesearch: {:ok, %{success: true}},
    voice_filesearch: {:ok, %{success: true}}
  }

  describe "run_all/2" do
    test "returns :ok for every node when each call/2 succeeds" do
      with_mocks(mock_calls(@all_ok)) do
        results = capture_run(1)

        assert Map.keys(results) |> Enum.sort() == Enum.sort(@nodes)
        assert Enum.all?(@nodes, fn node -> results[node] == :ok end)
      end
    end

    test "maps a typed error to {:error, reason} while the rest still run" do
      results_stub = %{@all_ok | geolocation: {:error, :empty_input, "Missing lat or long field"}}

      with_mocks(mock_calls(results_stub)) do
        results = capture_run(1)

        assert results["geolocation"] == {:error, "Missing lat or long field"}
        assert results["speech_to_text"] == :ok
        assert results["voice-filesearch-gpt"] == :ok
      end
    end

    test "maps a {:snooze, seconds} result to an error" do
      results_stub = %{@all_ok | speech_to_text: {:snooze, 5}}

      with_mocks(mock_calls(results_stub)) do
        results = capture_run(1)

        assert {:error, reason} = results["speech_to_text"]
        assert reason =~ "snoozed"
      end
    end

    test "catches a raised exception and reports it without aborting the run" do
      results_stub = %{@all_ok | filesearch: :__raise__}

      raising = fn _fields, _ctx -> raise RuntimeError, "kaapi unreachable" end

      with_mocks([
        {Geolocation, [], [call: fn _f, _c -> results_stub.geolocation end]},
        {SpeechToText, [], [call: fn _f, _c -> results_stub.speech_to_text end]},
        {TextToSpeech, [], [call: fn _f, _c -> results_stub.text_to_speech end]},
        {FilesearchGpt, [], [call: raising]},
        {VoiceFilesearchGpt, [], [call: fn _f, _c -> results_stub.voice_filesearch end]}
      ]) do
        results = capture_run(1)

        assert results["filesearch-gpt"] == {:error, "kaapi unreachable"}
        assert results["geolocation"] == :ok
      end
    end

    test "prints a per-node summary" do
      with_mocks(mock_calls(@all_ok)) do
        output = capture_io(fn -> SmokeTest.run_all(1) end)

        assert output =~ "Flow-webhook smoke test  org_id=1"
        assert output =~ "✓ geolocation"
        assert output =~ "✓ voice-filesearch-gpt"
      end
    end
  end

  describe "smoke-test sentinel suppression" do
    test "build_flow_resume_metadata/6 threads the sentinel from fields into request_metadata" do
      fields = %{"webhook_log_id" => nil, "result_name" => nil, "smoke_test" => true}
      {_url, metadata} = Kaapi.build_flow_resume_metadata(1, 10, 20, fields)
      assert metadata.smoke_test == true

      fields_without = %{"webhook_log_id" => nil, "result_name" => nil}
      {_url, metadata_without} = Kaapi.build_flow_resume_metadata(1, 10, 20, fields_without)
      refute Map.has_key?(metadata_without, :smoke_test)
    end

    test "maybe_upload_tts_audio/1 skips the GCS upload for a smoke callback" do
      response = %{"smoke_test" => true, "output_type" => "audio", "message" => "base64audio"}
      assert Webhook.maybe_upload_tts_audio(response) == response
    end

    test "resume/3 drops a signed smoke callback before Dispatcher.callback counts it" do
      contact = Fixtures.contact_fixture(%{organization_id: 1})
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

      signature =
        Glific.signature(
          1,
          Jason.encode!(%{
            "organization_id" => 1,
            "flow_id" => 99,
            "contact_id" => contact.id,
            "timestamp" => timestamp
          }),
          timestamp
        )

      response = %{
        "organization_id" => 1,
        "flow_id" => 99,
        "contact_id" => contact.id,
        "timestamp" => timestamp,
        "signature" => signature,
        "webhook_name" => "speech_to_text",
        "smoke_test" => true
      }

      with_mock Glific.Flows.Webhooks.Dispatcher,
        callback: fn _name, _result, _response -> %{} end do
        assert :ok = Webhook.resume(1, %{"success" => true}, response)
        assert_not_called(Glific.Flows.Webhooks.Dispatcher.callback(:_, :_, :_))
      end
    end
  end

  describe "run_scheduled/0" do
    setup do
      previous = Application.get_env(:glific, SmokeTest)
      on_exit(fn -> restore_env(previous) end)
      :ok
    end

    test "is a no-op that reports nothing when no canary org is configured" do
      Application.delete_env(:glific, SmokeTest)

      with_mock Glific, [:passthrough], log_error: fn message -> {:error, message} end do
        assert SmokeTest.run_scheduled() == :ok
        assert_not_called(Glific.log_error(:_))
      end
    end

    test "runs the probe and reports each failed node when a canary org is configured" do
      Application.put_env(:glific, SmokeTest, org_id: 1)
      results_stub = %{@all_ok | geolocation: {:error, :empty_input, "Missing lat or long field"}}

      with_mocks(
        mock_calls(results_stub) ++
          [{Glific, [:passthrough], [log_error: fn message -> {:error, message} end]}]
      ) do
        capture_io(fn -> assert SmokeTest.run_scheduled() == :ok end)

        assert_called(
          Glific.log_error(
            "Flow-webhook smoke test failed for geolocation: Missing lat or long field"
          )
        )

        assert_called_exactly(Glific.log_error(:_), 1)
      end
    end
  end

  @spec restore_env(keyword() | nil) :: :ok
  defp restore_env(nil), do: Application.delete_env(:glific, SmokeTest)
  defp restore_env(previous), do: Application.put_env(:glific, SmokeTest, previous)

  @spec capture_run(non_neg_integer()) :: %{String.t() => SmokeTest.outcome()}
  defp capture_run(organization_id) do
    {result, _io} = with_io(fn -> SmokeTest.run_all(organization_id) end)
    result
  end
end
