defmodule Glific.Bhasini.BhasiniTest do
  use Glific.DataCase

  alias Glific.Bhasini

  test "get_iso_code/2  should language iso_code" do
    language_list = [
      "tamil",
      "kannada",
      "malayalam",
      "telugu",
      "assamese",
      "gujarati",
      "bengali",
      "punjabi",
      "marathi",
      "urdu",
      "spanish",
      "english",
      "hindi"
    ]

    assert ["hi", "en", "es", "ur", "mr", "pa", "bn", "gu", "as", "te", "ml", "kn", "ta"] ==
             Enum.reduce(language_list, [], fn language, acc ->
               returned_code = Bhasini.get_iso_code(language, "iso_639_1")
               [returned_code | acc]
             end)
  end

  @tag :skip
  test "download_encoded_file/2 should download encoded file, convert it to mp3 and return ok tuple" do
    uuid = Ecto.UUID.generate()

    response = %{
      "pipelineResponse" => [
        %{
          "audio" => [
            %{
              "audioContent" => "aGVsbG8gdGhlcmUsIHdlbGNvbWUgdG8gR2xpZml4",
              "audioUri" => nil
            }
          ],
          "config" => %{
            "audioFormat" => "wav",
            "encoding" => "base64",
            "language" => %{"sourceLanguage" => "en", "sourceScriptCode" => ""},
            "samplingRate" => 8000
          },
          "output" => nil,
          "taskType" => "tts"
        }
      ]
    }

    file_path = System.tmp_dir!() <> "#{uuid}.mp3"
    assert {:ok, file_path} == Bhasini.download_encoded_file(response, uuid)
  end
end
