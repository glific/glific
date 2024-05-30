defmodule Glific.OpenAI.ChatGPTTest do
  use Glific.DataCase

  alias Glific.OpenAI.ChatGPT

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
end
