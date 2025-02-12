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

  test "fetch_thread/1  fetches an existing thread and returns {:ok, thread_id} " do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body:
          "{\n  \"id\": \"thread_uRNWRC9e6Rg95ul95rzWVPuV\",\n  \"object\": \"thread\",\n  \"created_at\": 1717048859,\n  \"metadata\": {},\n  \"tool_resources\": {\n    \"code_interpreter\": {\n      \"file_ids\": []\n    }\n  }\n}"
      }
    end)

    assert {:ok, "thread_uRNWRC9e6Rg95ul95rzWVPuV"} ==
             ChatGPT.fetch_thread(%{thread_id: "thread_uRNWRC9e6Rg95ul95rzWVPuV"})

    # passing nil value should return error map
    {:error, error} = ChatGPT.fetch_thread(%{thread_id: nil})
    assert error == "No thread found with nil id."
  end

  test "fetch_thread/1  fetches an existing thread with incorrect id and returns map with error message" do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 404,
        body:
          "{\n  \"error\": {\n    \"message\": \"No thread found with id 'thread_uRNWRC9e6Rg95ul95rzWVPuVs'.\",\n    \"type\": \"invalid_request_error\",\n    \"param\": null,\n    \"code\": null\n  }\n}"
      }
    end)

    {:error, error} =
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

  test "create_and_run_thread/1 should create a new thread with message and return run_id" do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body:
          "{\"assistant_id\":\"asst_fz7oIQ2goRLfrP1mWceasdfse\",\"created_at\":1738814284,\"expires_at\":1738814884,\"id\":\"run_eJmCMSEHx4tQEeWVA6XqvTRU\",\"instructions\":\"**You are an AI assistant designed to help officials by answering their questions based on provided policy documents\",\"model\":\"gpt-4o\",\"object\":\"thread.run\",\"status\":\"queued\",\"thread_id\":\"thread_M3tgrpBy5mtsFx3YWBpQn4FH\"}"
      }
    end)

    params = %{
      question: "What is the role of VGF for CLF",
      assistant_id: "asst_fz7oIQ2goRLfrP1mWceasdfse"
    }

    {:ok, response} = ChatGPT.create_and_run_thread(params)

    assert get_in(response, ["id"]) == "run_eJmCMSEHx4tQEeWVA6XqvTRU"
  end

  test "create_and_run_thread/1 with empty message should return error" do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 400,
        body:
          "{\n  \"error\": {\n    \"message\": \"Message content must be non-empty.\",\n    \"type\": \"invalid_request_error\",\n    \"param\": \"content\",\n    \"code\": null\n  }\n}"
      }
    end)

    params = %{
      question: "",
      assistant_id: "asst_fz7oIQ2goRLfrP1mWceasdfse"
    }

    {:error, error} = ChatGPT.create_and_run_thread(params)

    assert error ==
             "Invalid response while creating and running thread \"Message content must be non-empty.\""
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

  test "remove_citation/2 should remove citations from the GPT response" do
    message =
      "Childhood pregnancy can cause many problems for both the mother and the baby. Some of the issues include:\n\n1. Higher risk of complications during pregnancy and childbirth, such as anemia, high blood pressure, and premature birth【4:2†source】【4:5†source】.\n2. Increased chances of delivering low birth weight babies, which can lead to health problems for the baby【4:2†source】.\n3. Emotional and mental stress, which can affect both the mother and the baby's health【4:16†source】.\n4. Lack of proper nutrition and healthcare, which can impact the growth and development of the baby【4:12†source】.\n\nIt is important for young mothers to get proper medical care and support during pregnancy."

    thread_message_params = %{
      "assistant_id" => "asst_eFPyq1m3zcvm6VkPBSQYz4Np",
      "message" => message,
      "success" => true,
      "thread_id" => "thread_3dhwQYN1xMATT1LsauUXNlYo"
    }

    cleaned_thread_params =
      ChatGPT.remove_citation(thread_message_params, true)

    assert cleaned_thread_params["message"] ==
             "Childhood pregnancy can cause many problems for both the mother and the baby. Some of the issues include:\n\n1. Higher risk of complications during pregnancy and childbirth, such as anemia, high blood pressure, and premature birth.\n2. Increased chances of delivering low birth weight babies, which can lead to health problems for the baby.\n3. Emotional and mental stress, which can affect both the mother and the baby's health.\n4. Lack of proper nutrition and healthcare, which can impact the growth and development of the baby.\n\nIt is important for young mothers to get proper medical care and support during pregnancy."

    # should return default message when remove_citation is set to false
    cleaned_thread_params =
      ChatGPT.remove_citation(thread_message_params, false)

    assert cleaned_thread_params["message"] == message
  end

  test "remove_citation/2 should remove citations from the GPT response for updated format as well" do
    message =
      "Childhood pregnancy can cause many problems for both the mother and the baby. Some of the issues include:\n\n1. Higher risk of complications during pregnancy and childbirth, such as anemia, high blood pressure, and premature birth【4:0†TEst W1q1.pdf】."

    thread_message_params = %{
      "assistant_id" => "asst_eFPyq1m3zcvm6Vkxsdfsep",
      "message" => message,
      "success" => true
    }

    cleaned_thread_params =
      ChatGPT.remove_citation(thread_message_params, true)

    assert cleaned_thread_params["message"] ==
             "Childhood pregnancy can cause many problems for both the mother and the baby. Some of the issues include:\n\n1. Higher risk of complications during pregnancy and childbirth, such as anemia, high blood pressure, and premature birth."

    # should return default message when remove_citation is set to false
    cleaned_thread_params =
      ChatGPT.remove_citation(thread_message_params, false)

    assert cleaned_thread_params["message"] == message
  end

  test "retrieve_assistant/1  fetches an existing assistant with incorrect id and returns map with error message" do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 404,
        body:
          "{\n  \"error\": {\n    \"message\": \"No assistant found with id 'asst_GIqJAImBf800RWaxsadfs'.\",\n    \"type\": \"invalid_request_error\",\n    \"param\": null,\n    \"code\": null\n  }\n}"
      }
    end)

    {:error, error} = ChatGPT.retrieve_assistant("asst_GIqJAImBf800RWaxsadfs")

    assert error == "No assistant found with id 'asst_GIqJAImBf800RWaxsadfs'."
  end

  test "retrieve_assistant/1  fetches an existing assistant with correct id and returns ok tuple with assistant name" do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body:
          "{\n  \"id\": \"asst_GIqyCU4atuRWax\",\n  \"object\": \"assistant\",\n  \"created_at\": 1723531767,\n  \"name\": \"Diagnosis BOT\",\n  \"description\": null,\n  \"model\": \"gpt-4o\",\n  \"instructions\": \"You are a medical assistant specializing in identifying disabilities.\\\"\",\n  \"tools\": [\n    {\n      \"type\": \"file_search\"\n    }\n  ],\n  \"top_p\": 1.0,\n  \"temperature\": 0.0,\n  \"tool_resources\": {\n    \"file_search\": {\n      \"vector_store_ids\": [\n        \"vs_xUZaQSr3sdfsdpF\"\n      ]\n    }\n  },\n  \"metadata\": {},\n  \"response_format\": \"auto\"\n}"
      }
    end)

    {:ok, assistant_name} = ChatGPT.retrieve_assistant("asst_GIqJAImBf800RWaxsadfs")

    assert assistant_name == "Diagnosis BOT"
  end
end
