defmodule Glific.Flows.Translate.GoogleTranslateTest do
  use Glific.DataCase, async: false

  alias Glific.{
    Fixtures,
    Flows.Translate.GoogleTranslate,
    Flows.Translate.Translate
  }

  import Tesla.Mock

  setup_all do
    mock_global(&default_mock/1)
    :ok
  end

  # `GoogleTranslate.translate/4` fires its HTTP calls from inside `Task.async_stream`-spawned
  # processes, so `Tesla.Mock.mock/1` (process-local) never sees them -- only `mock_global/1`
  # reaches those. Kept as a named function so error-path tests can restore it via `on_exit`
  # after overriding the global mock for their own scenario.
  defp default_mock(env) do
    cond do
      String.contains?(env.body, "HelloWorld") ->
        %Tesla.Env{
          body: %{
            "data" => %{
              "translations" => [
                %{"translatedText" => "नमस्ते दुनिया"}
              ]
            }
          },
          status: 200
        }

      String.contains?(env.body, "nice to meet you") ->
        %Tesla.Env{
          body: %{
            "data" => %{
              "translations" => [
                %{"translatedText" => "आपसे मिलकर अच्छा लगा"}
              ]
            }
          },
          status: 200
        }

      String.contains?(env.body, "@contact.name is this youe name") ->
        %Tesla.Env{
          body: %{
            "data" => %{
              "translations" => [
                %{"translatedText" => "@contact.name क्या यह आपका नाम है"}
              ]
            }
          },
          status: 200
        }

      String.contains?(env.body, "@contact.name") ->
        %Tesla.Env{
          body: %{
            "data" => %{
              "translations" => [
                %{"translatedText" => "@संपर्क नाम"}
              ]
            }
          },
          status: 200
        }

      true ->
        %Tesla.Env{
          status: 200,
          body: %{
            "data" => %{
              "translations" => [
                %{"translatedText" => "बड़े संदेशों के लिए अनुवाद उपलब्ध नहीं है"}
              ]
            }
          }
        }
    end
  end

  test "translate/3 basic translation test" do
    org_id = Repo.get_organization_id()

    {:ok, translated_text} =
      GoogleTranslate.translate(
        ["HelloWorld", "nice to meet you"],
        "en",
        "hi",
        org_id: org_id
      )

    assert translated_text == ["नमस्ते दुनिया", "आपसे मिलकर अच्छा लगा"]

    # when long text is also part of the list
    long_text = Faker.Lorem.sentence(250)

    {:ok, translated_text} =
      GoogleTranslate.translate(["HelloWorld", long_text], "en", "hi", org_id: org_id)

    assert translated_text == ["नमस्ते दुनिया", "बड़े संदेशों के लिए अनुवाद उपलब्ध नहीं है"]
  end

  test "translate/3 returns an error instead of silently persisting a blank translation on a hard API failure" do
    org_id = Fixtures.get_org_id()

    Tesla.Mock.mock_global(fn _env ->
      %Tesla.Env{
        status: 500,
        body: %{
          "error" => %{
            "message" => "invalid response"
          }
        }
      }
    end)

    on_exit(fn -> Tesla.Mock.mock_global(&default_mock/1) end)

    string = ["Some text to translate"]
    src = "english"
    dst = "hindi"

    assert {:error, reason} = GoogleTranslate.translate(string, src, dst, org_id: org_id)
    assert reason =~ "Translation has failed"
    assert reason =~ "reach out to the Glific team"
  end

  test "translate/3 surfaces the Google 403 API_KEY_SERVICE_BLOCKED error" do
    org_id = Fixtures.get_org_id()

    Tesla.Mock.mock_global(fn _env ->
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

    on_exit(fn -> Tesla.Mock.mock_global(&default_mock/1) end)

    assert {:error, reason} =
             GoogleTranslate.translate(["Some text to translate"], "english", "hindi",
               org_id: org_id
             )

    assert reason =~ "Translation has failed"
    assert reason =~ "reach out to the Glific team"
  end

  test "check_large_strings/1 handles mix of short and long strings" do
    # heck_large_strings/1 returns original list when all strings are within token limit
    strings = ["HelloWorld", "Nice to meet you"]
    result = Translate.check_large_strings(strings)
    assert result == ["Nice to meet you", "HelloWorld"]

    # when long text is at the beginning
    short_text = "Hello"
    long_text = Faker.Lorem.sentence(250)
    strings = [long_text, short_text, "World"]
    result = Translate.check_large_strings(strings)
    assert result == ["World", "Hello", "translation not available for long messages"]
  end

  test "translate/3 translation of contact variables with text" do
    org_id = Repo.get_organization_id()

    {:ok, translated_text} =
      GoogleTranslate.translate(
        ["@contact.name is this youe name"],
        "en",
        "hi",
        org_id: org_id
      )

    assert translated_text == ["@contact.name क्या यह आपका नाम है"]
  end

  test "translate/3 translation of contact variables" do
    org_id = Repo.get_organization_id()

    {:ok, translated_text} =
      GoogleTranslate.translate(
        ["@contact.name"],
        "en",
        "hi",
        org_id: org_id
      )

    expected_result = ["@contact.name"]

    assert translated_text == expected_result
  end
end
