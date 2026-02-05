defmodule Glific.Providers.Gupshup.ApiClientTest do
  use ExUnit.Case

  alias Glific.Providers.Gupshup.ApiClient

  describe "download_media_content/2" do
    test "returns base64 encoded content on successful download" do
      Tesla.Mock.mock(fn
        %{method: :get, url: "https://example.com/media/audio.mp3"} ->
          %Tesla.Env{
            status: 200,
            body: <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46>>
          }
      end)

      assert {:ok, encoded} =
               ApiClient.download_media_content("https://example.com/media/audio.mp3", 1)

      assert encoded ==
               Base.encode64(<<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46>>)
    end

    test "returns error on non-200 status code" do
      Tesla.Mock.mock(fn
        %{method: :get, url: "https://example.com/media/missing.mp3"} ->
          %Tesla.Env{status: 404, body: "Not Found"}
      end)

      assert {:error, :download_failed} =
               ApiClient.download_media_content("https://example.com/media/missing.mp3", 1)
    end

    test "returns error on 500 status code" do
      Tesla.Mock.mock(fn
        %{method: :get, url: "https://example.com/media/error.mp3"} ->
          %Tesla.Env{status: 500, body: "Internal Server Error"}
      end)

      assert {:error, :download_failed} =
               ApiClient.download_media_content("https://example.com/media/error.mp3", 1)
    end

    test "returns error on network failure" do
      Tesla.Mock.mock(fn
        %{method: :get, url: "https://example.com/media/timeout.mp3"} ->
          {:error, :timeout}
      end)

      assert {:error, :download_failed} =
               ApiClient.download_media_content("https://example.com/media/timeout.mp3", 1)
    end
  end
end
