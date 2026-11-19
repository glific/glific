defmodule Glific.MimeTypesTest do
  @moduledoc """
  Guards media classification end to end.

  Two things can break it independently: the extension lists in
  `Glific.Messages.get_media_type_from_url/2`, and mime's own type table, which is
  read at compile time from `config :mime, :types`.
  """

  use ExUnit.Case, async: true

  alias Glific.Messages

  @media %{
    "png" => {:image, "image/png"},
    "jpg" => {:image, "image/jpeg"},
    "jpeg" => {:image, "image/jpeg"},
    "webp" => {:sticker, "image/webp"},
    "mp4" => {:video, "video/mp4"},
    "3gp" => {:video, "video/3gpp"},
    "3gpp" => {:video, "video/3gpp"},
    "mp3" => {:audio, "audio/mpeg"},
    "wav" => {:audio, "audio/wav"},
    "aac" => {:audio, "audio/aac"},
    "ogg" => {:audio, "audio/ogg"},
    "pdf" => {:document, "application/pdf"},
    "docx" =>
      {:document, "application/vnd.openxmlformats-officedocument.wordprocessingml.document"},
    "xlsx" => {:document, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}
  }

  test "Glific classifies every media format it accepts" do
    for {extension, {kind, _type}} <- @media do
      url = "https://example.com/file.#{extension}"

      assert Messages.get_media_type_from_url(url, log_error: false) == {kind, url},
             ".#{extension} classified as " <>
               "#{inspect(Messages.get_media_type_from_url(url, log_error: false))}, " <>
               "expected #{inspect({kind, url})}"
    end
  end

  test "mime resolves the content type each of those is stored and sent with" do
    for {extension, {_kind, type}} <- @media do
      assert MIME.from_path("file.#{extension}") == type
    end
  end
end
