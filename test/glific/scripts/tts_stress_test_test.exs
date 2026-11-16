defmodule Glific.Scripts.TtsStressTestTest do
  use Glific.DataCase

  import ExUnit.CaptureIO
  import Mock

  alias Glific.{Partners, Scripts.TtsStressTest}

  defp sample_wav_audio do
    samples = :binary.copy(<<0::16>>, 2400)
    data_size = byte_size(samples)

    <<"RIFF", 36 + data_size::32-little, "WAVE", "fmt ", 16::32-little, 1::16-little,
      1::16-little, 24_000::32-little, 48_000::32-little, 2::16-little, 16::16-little, "data",
      data_size::32-little>> <> samples
  end

  test "run/2 :temp_cleanup leaves no temp files after converting audio", %{
    organization_id: organization_id
  } do
    {:ok, _credential} =
      Partners.create_credential(%{
        shortcode: "google_cloud_storage",
        organization_id: organization_id,
        is_active: true
      })

    test_pid = self()
    audio_data = Base.encode64(sample_wav_audio())

    Tesla.Mock.mock(fn %{method: :post} ->
      %Tesla.Env{
        status: 200,
        body: %{
          candidates: [%{content: %{parts: [%{inlineData: %{data: audio_data}}]}}],
          usageMetadata: %{totalTokenCount: 10}
        }
      }
    end)

    # CI has no ffmpeg; stand in for it by writing the MP3 it would produce.
    with_mocks([
      {System, [:passthrough],
       cmd: fn "ffmpeg", args, _opts ->
         [audio_file, mp3_file] = Enum.take(args, -2)
         send(test_pid, {:converted, audio_file, mp3_file})
         File.write!(mp3_file, "mp3")
         {"", 0}
       end},
      {Glific.GCS.GcsWorker, [],
       upload_media: fn _mp3_file, _remote_name, _organization_id ->
         {:ok, %{url: "https://storage.googleapis.com/bucket/test.mp3"}}
       end}
    ]) do
      output = capture_io(fn -> TtsStressTest.run(organization_id, :temp_cleanup) end)

      for _ <- 1..5 do
        assert_received {:converted, audio_file, mp3_file}
        assert Path.dirname(audio_file) == System.tmp_dir!() |> Path.expand()
        refute File.exists?(audio_file)
        refute File.exists?(mp3_file)
      end

      assert output =~ "Run 5: ✓ clean"
      assert output =~ "Net temp files: 0"
    end
  end
end
