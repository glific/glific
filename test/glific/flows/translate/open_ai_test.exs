defmodule Glific.Flows.Translate.OpenAITest do
  use Glific.DataCase

  alias Glific.Flows.Translate.OpenAI

  setup do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            "choices" => [
              %{
                "message" => %{
                  "content" =>
                    "[\"हमारे एनजीओ चैटबॉट में आपका स्वागत है\", \"हमें अपने बारे में परिचय देने के लिए धन्यवाद\" ]"
                }
              }
            ]
          }
        }
    end)

    :ok
  end

  test "translate/3 should chunk a list of strings based on length" do
    {:ok, translated_text} =
      OpenAI.translate(
        ["Welcome to our NGO Chatbot", "Thank you for introducing yourself to us"],
        "english",
        "hindi"
      )

    assert translated_text == ["हमारे एनजीओ चैटबॉट में आपका स्वागत है", "हमें अपने बारे में परिचय देने के लिए धन्यवाद"]
  end

  test "chunk/1 should chunk a list of strings based on length" do
    long_text = Faker.Lorem.sentence(250)

    # when long text is at the middle
    response = [
      ["thankyou for joining", "translation not available for long messages", "correct answer"]
    ]

    assert response == OpenAI.chunk(["thankyou for joining", long_text, "correct answer"])

    # when long text is at the end
    response = [
      ["thankyou for joining", "correct answer", "translation not available for long messages"]
    ]

    assert response == OpenAI.chunk(["thankyou for joining", "correct answer", long_text])

    # when long text is at the beginning
    response = [
      ["translation not available for long messages", "thankyou for joining", "correct answer"]
    ]

    assert response == OpenAI.chunk([long_text, "thankyou for joining", "correct answer"])
  end
end
