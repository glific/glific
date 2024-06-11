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

  test "create_thread/1  creates a new thread" do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body:
          "{\n  \"id\": \"thread_sst2q6k3SLBjPBTysLeLDG9K\",\n  \"object\": \"thread\",\n  \"created_at\": 1717086012,\n  \"metadata\": {},\n  \"tool_resources\": {}\n}"
      }
    end)

    thread = ChatGPT.create_thread()
    assert thread["id"] == "thread_sst2q6k3SLBjPBTysLeLDG9K"
    assert thread["created_at"] == 1_717_086_012
  end

  test "fetch_thread/1  fetches an existing thread and returns %{success: true} " do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body:
          "{\n  \"id\": \"thread_uRNWRC9e6Rg95ul95rzWVPuV\",\n  \"object\": \"thread\",\n  \"created_at\": 1717048859,\n  \"metadata\": {},\n  \"tool_resources\": {\n    \"code_interpreter\": {\n      \"file_ids\": []\n    }\n  }\n}"
      }
    end)

    assert %{success: true} ==
             ChatGPT.fetch_thread(%{thread_id: "thread_uRNWRC9e6Rg95ul95rzWVPuV"})

    # passing nil value should return error map
    response = ChatGPT.fetch_thread(%{thread_id: nil})
    assert response.error == "invalid thread ID"
  end

  test "fetch_thread/1  fetches an existing thread with incorrect id and returns map with error message" do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 404,
        body:
          "{\n  \"error\": {\n    \"message\": \"No thread found with id 'thread_uRNWRC9e6Rg95ul95rzWVPuVs'.\",\n    \"type\": \"invalid_request_error\",\n    \"param\": null,\n    \"code\": null\n  }\n}"
      }
    end)

    %{success: false, error: error} =
      ChatGPT.fetch_thread(%{thread_id: "thread_uRNWRC9e6Rg95ul95rzWVPuV"})

    assert error == "No thread found with id 'thread_uRNWRC9e6Rg95ul95rzWVPuVs'."
  end

  test "add_message_to_thread/1 add user's question as a message to the thread" do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body:
          "{\n  \"id\": \"msg_mWMdmAjzT8EuWJ0r39hP5iu3\",\n  \"object\": \"thread.message\",\n  \"created_at\": 1717087602,\n  \"assistant_id\": null,\n  \"thread_id\": \"thread_sst2q6k3SLBjPBTysLeLDG9K\",\n  \"run_id\": null,\n  \"role\": \"user\",\n  \"content\": [\n    {\n      \"type\": \"text\",\n      \"text\": {\n        \"value\": \"how  to get started with creating flow\",\n        \"annotations\": []\n      }\n    }\n  ],\n  \"attachments\": [],\n  \"metadata\": {}\n}"
      }
    end)

    params = %{
      question: "how  to get started with creating flow",
      thread_id: "thread_qlbXMrY8CsdLZwRdKnzr81eF",
      assistant_id: "asst_QdmawsEVZhnvq9Nzfq11fjIX"
    }

    response = ChatGPT.add_message_to_thread(params)

    assert get_in(response, ["content", Access.at(0), "text", "value"]) ==
             "how  to get started with creating flow"
  end

  test "list_thread_messages/1 should list all the messages in the thread" do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body:
          "{\n  \"object\": \"list\",\n  \"data\": [\n    {\n      \"id\": \"msg_mWMdmAjzT8EuWJ0r39hP5iu3\",\n      \"object\": \"thread.message\",\n      \"created_at\": 1717087602,\n      \"assistant_id\": null,\n      \"thread_id\": \"thread_qlbXMrY8CsdLZwRdKnzr81eF\",\n      \"run_id\": null,\n      \"role\": \"user\",\n      \"content\": [\n        {\n          \"type\": \"text\",\n          \"text\": {\n            \"value\": \"how  to get started with creating flow\",\n            \"annotations\": []\n          }\n        }\n      ],\n      \"attachments\": [],\n      \"metadata\": {}\n    }\n  ],\n  \"first_id\": \"msg_mWMdmAjzT8EuWJ0r39hP5iu3\",\n  \"last_id\": \"msg_mWMdmAjzT8EuWJ0r39hP5iu3\",\n  \"has_more\": false\n}"
      }
    end)

    last_message = ChatGPT.list_thread_messages(%{thread_id: "thread_qlbXMrY8CsdLZwRdKnzr81eF"})
    assert last_message["message"] == "how  to get started with creating flow"
    assert last_message["thread_id"] == "thread_qlbXMrY8CsdLZwRdKnzr81eF"
  end
end
