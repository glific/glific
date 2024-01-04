defmodule Glific.Flows.Translate.OpenAITest do
  use Glific.DataCase

  alias Glific.Flows.Translate.OpenAI

  test "chunk/1 should chunk a list of strings based on length" do
    long_text = Faker.String.base64(18000)

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
