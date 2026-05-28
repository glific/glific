defmodule Glific.OpenAI.ChatGPTTest do
  use Glific.DataCase

  alias Glific.OpenAI.ChatGPT

  test "gpt_vision/1  should takes url and prompt and return the analysis of image" do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "content" =>
                  "This image depicts a scenic view of a sunset or sunrise with a field of flowers silhouetted against the light. The bright sun is low on the horizon, casting a warm glow and causing dramatic lighting and shadows among the silhouetted flowers and stems. The sky has a mix of colors, typical of such time of day, with clouds illuminated by the sun. The text overlaying the image reads \"JPEG This is Sample Image.\"",
                "role" => "assistant"
              }
            }
          ],
          "created" => 1_717_089_925,
          "model" => "gpt-4o-2024-05-13"
        }
      }
    end)

    {:ok, response} =
      ChatGPT.gpt_vision(%{
        "prompt" => "what's in the image",
        "url" => "https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample02.jpg"
      })

    assert response ==
             "This image depicts a scenic view of a sunset or sunrise with a field of flowers silhouetted against the light. The bright sun is low on the horizon, casting a warm glow and causing dramatic lighting and shadows among the silhouetted flowers and stems. The sky has a mix of colors, typical of such time of day, with clouds illuminated by the sun. The text overlaying the image reads \"JPEG This is Sample Image.\""
  end
end
