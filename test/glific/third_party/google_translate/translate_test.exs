defmodule Glific.GoogleTranslate.TranslateTest do
  use Glific.DataCase
  import Tesla.Mock

  alias Glific.GoogleTranslate.Translate

  @languages %{"source" => "en", "target" => "hi"}

  describe "parse/3" do
    test "returns translated text on a 200 response" do
      mock(fn _env ->
        %Tesla.Env{
          status: 200,
          body: %{
            "data" => %{
              "translations" => [%{"translatedText" => "नमस्ते दुनिया"}]
            }
          }
        }
      end)

      assert {:ok, "नमस्ते दुनिया"} = Translate.parse("api_key", "Hello World", @languages)
    end

    test "surfaces the HTTP status and Google error reason on a 403 API_KEY_SERVICE_BLOCKED response" do
      mock(fn _env ->
        %Tesla.Env{
          status: 403,
          body: %{
            "error" => %{
              "code" => 403,
              "status" => "PERMISSION_DENIED",
              "message" =>
                "Requests to this API translate method google.cloud.translate.v2.TranslateService.TranslateText are blocked.",
              "details" => [%{"reason" => "API_KEY_SERVICE_BLOCKED"}]
            }
          }
        }
      end)

      assert {:error, reason} = Translate.parse("bad_api_key", "Hello World", @languages)
      assert reason =~ "403"
      assert reason =~ "API_KEY_SERVICE_BLOCKED"
      assert reason =~ "blocked"
    end

    test "surfaces the HTTP status and message for other non-200 responses" do
      mock(fn _env ->
        %Tesla.Env{
          status: 500,
          body: %{"error" => %{"message" => "internal error"}}
        }
      end)

      assert {:error, reason} = Translate.parse("api_key", "Hello World", @languages)
      assert reason =~ "500"
      assert reason =~ "internal error"
    end

    test "does not leak the API key when the transport call itself fails" do
      mock(fn _env -> {:error, :timeout} end)

      assert {:error, reason} = Translate.parse("super-secret-api-key", "Hello World", @languages)
      refute reason =~ "super-secret-api-key"
    end
  end
end
