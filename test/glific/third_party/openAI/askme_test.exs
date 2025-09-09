defmodule Glific.ThirdParty.OpenAI.AskmeTest do
  use Glific.DataCase, async: true
  import Tesla.Mock

  alias Glific.ThirdParty.OpenAI.AskmeBot

  @endpoint "https://api.openai.com/v1/responses"

  setup do
    Application.put_env(:glific, :askme_bot_vector_store_id, "vs_xyz")
    :ok
  end

  test "askme/1 returns the response successfully" do
    expected_text =
      """
      A flow in Glific is a structured sequence of interactions designed to facilitate communication with contacts or beneficiaries. It consists of several nodes, each representing a step that can include sending messages, waiting for user responses, or executing specific actions based on user inputs. Flows are triggered by specific keywords, which enable dynamic engagement with users.
      When creating a flow, you define its name and the keywords that will trigger it. Additionally, flows can have parent-child relationships, allowing for better management of data sharing between them.
      For more detailed information, you can refer to the documentation here: [Flow Overview](https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Overview) .
      """
      |> String.trim()

    mock(fn
      %{
        method: :post,
        url: @endpoint
      } ->
        %Tesla.Env{
          status: 200,
          body: %{
            "output" => [
              %{
                "id" => "fs_x",
                "queries" => ["What is a flow?"],
                "status" => "completed",
                "type" => "file_search_call"
              },
              %{
                "id" => "msg_y",
                "role" => "assistant",
                "status" => "completed",
                "type" => "message",
                "content" => [
                  %{
                    "type" => "output_text",
                    "text" => expected_text
                  }
                ]
              }
            ]
          }
        }
    end)

    params = %{
      "input" => [
        %{"content" => "what is a flow?", "role" => "user"}
      ]
    }

    assert {:ok, content} = AskmeBot.askme(params)
    assert content == expected_text
  end

  test "askme/1 failure cases" do
    mock(fn
      %{method: :post, url: @endpoint} ->
        {:error, :timeout}
    end)

    assert {:error, msg} = AskmeBot.askme(%{"input" => []})
    assert msg =~ "HTTP error calling OpenAI: :timeout"
  end
end
