defmodule Glific.Flows.Translate.GoogleTranslateTest do
  use Glific.DataCase, async: false

  alias Glific.Flows.Translate.GoogleTranslate

  import Tesla.Mock

  setup_all do
    mock_global(fn env ->
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
    end)

    :ok
  end

  test "translate/3 basic translation test" do
    {:ok, translated_text} =
      GoogleTranslate.translate(
        ["HelloWorld", "nice to meet you"],
        "en",
        "hi"
      )

    assert translated_text == ["नमस्ते दुनिया", "आपसे मिलकर अच्छा लगा"]

    # when long text is also part of the list
    long_text = Faker.Lorem.sentence(250)

    {:ok, translated_text} =
      GoogleTranslate.translate(["HelloWorld", long_text], "en", "hi")

    assert translated_text == ["नमस्ते दुनिया", "बड़े संदेशों के लिए अनुवाद उपलब्ध नहीं है"]
  end

  test "translate/3 test the possible errors" do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 500,
        body: %{
          "error" => %{
            "message" => "invalid response"
          }
        }
      }
    end)

    string = ["Some text to translate"]
    src = "english"
    dst = "hindi"

    {:ok, response} = GoogleTranslate.translate(string, src, dst)
    assert response == [["Could not translate, Try again"]]
  end

  test "check_large_strings/1 returns original list when all strings are within token limit" do
    strings = ["HelloWorld", "Nice to meet you"]
    result = GoogleTranslate.check_large_strings(strings)
    assert result == ["Nice to meet you", "HelloWorld"]
  end

  test "check_large_strings/1 replaces long strings exceeding token threshold with warning" do
    long_text = Faker.Lorem.sentence(250)
    strings = ["Hello", long_text, "World"]
    result = GoogleTranslate.check_large_strings(strings)
    assert result == ["World", "translation not available for long messages", "Hello"]
  end

  test "check_large_strings/1 handles mix of short and long strings" do
    # when long text is at the beginning
    short_text = "Hello"
    long_text = Faker.Lorem.sentence(250)
    strings = [long_text, short_text, "World"]
    result = GoogleTranslate.check_large_strings(strings)
    assert result == ["World", "Hello", "translation not available for long messages"]
  end
end
