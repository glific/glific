defmodule Glific.MimeTypesTest do
  @moduledoc """
  mime reads `config :mime, :types` through `Application.compile_env/3`, so the
  mapping only exists if the dep was compiled after the config was set. These
  assertions fail on a stale `_build` rather than letting media upload silently
  as application/octet-stream.
  """

  use ExUnit.Case, async: true

  test "every media format Glific accepts resolves to its real content type" do
    expected = %{
      "png" => "image/png",
      "jpg" => "image/jpeg",
      "jpeg" => "image/jpeg",
      "webp" => "image/webp",
      "mp4" => "video/mp4",
      "3gp" => "video/3gpp",
      "3gpp" => "video/3gpp",
      "mp3" => "audio/mpeg",
      "wav" => "audio/wav",
      "aac" => "audio/aac",
      "amr" => "audio/amr",
      "m4a" => "audio/mp4",
      "ogg" => "audio/ogg",
      "oga" => "audio/ogg",
      "pdf" => "application/pdf"
    }

    for {extension, type} <- expected do
      assert MIME.from_path("file.#{extension}") == type,
             "#{extension} resolved to #{MIME.from_path("file.#{extension}")}, expected #{type}. "
    end
  end
end
