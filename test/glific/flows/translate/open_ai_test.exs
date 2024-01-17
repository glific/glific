defmodule Glific.Flows.Translate.OpenAITest do
  use Glific.DataCase, async: false

  alias Glific.Flows.Translate.OpenAI

  import Tesla.Mock

  setup do
    mock_global(fn env ->
      cond do
        String.contains?(env.body, "Welcome to our NGO Chatbot") ->
          %Tesla.Env{
            status: 200,
            body: %{
              "choices" => [
                %{
                  "message" => %{
                    "content" => "हमारे एनजीओ चैटबॉट में आपका स्वागत है"
                  }
                }
              ]
            }
          }

        String.contains?(env.body, "Thank you for introducing yourself to us") ->
          %Tesla.Env{
            status: 200,
            body: %{
              "choices" => [
                %{
                  "message" => %{
                    "content" => "हमें अपने बारे में परिचय देने के लिए धन्यवाद"
                  }
                }
              ]
            }
          }

        true ->
          %Tesla.Env{
            status: 200,
            body: %{
              "choices" => [
                %{
                  "message" => %{
                    "content" => "बड़े संदेशों के लिए अनुवाद उपलब्ध नहीं है।"
                  }
                }
              ]
            }
          }
      end
    end)

    :ok
  end

  test "translate/3 should translate list of strings" do
    {:ok, translated_text} =
      OpenAI.translate(
        ["Welcome to our NGO Chatbot", "Thank you for introducing yourself to us"],
        "english",
        "hindi"
      )

    assert translated_text == ["हमारे एनजीओ चैटबॉट में आपका स्वागत है", "हमें अपने बारे में परिचय देने के लिए धन्यवाद"]

    # when long text is also part of list
    long_text = Faker.Lorem.sentence(250)

    {:ok, translated_text} =
      OpenAI.translate(["Welcome to our NGO Chatbot", long_text], "english", "hindi")

    assert translated_text == ["हमारे एनजीओ चैटबॉट में आपका स्वागत है", "बड़े संदेशों के लिए अनुवाद उपलब्ध नहीं है।"]
  end

  test "check_large_strings/1 should replace long strings with warning" do
    long_text = Faker.Lorem.sentence(250)

    # when long text is at the middle
    response = [
      "thankyou for joining",
      "translation not available for long messages",
      "correct answer"
    ]

    assert response ==
             OpenAI.check_large_strings(["correct answer", long_text, "thankyou for joining"])

    # when long text is at the end
    response = [
      "thankyou for joining",
      "correct answer",
      "translation not available for long messages"
    ]

    assert response ==
             OpenAI.check_large_strings([long_text, "correct answer", "thankyou for joining"])

    # when long text is at the beginning
    response = [
      "correct answer",
      "thankyou for joining",
      "translation not available for long messages"
    ]

    assert response ==
             OpenAI.check_large_strings([long_text, "thankyou for joining", "correct answer"])
  end
end
