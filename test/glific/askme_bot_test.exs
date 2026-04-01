defmodule Glific.AskmeBotTest do
  use Glific.DataCase

  alias Glific.AskmeBot
  alias Glific.AskmeBot.Conversation
  alias Glific.Repo

  @dify_success_response %{
    "answer" => "Glific is a two-way communication platform.",
    "conversation_id" => "conv-abc-123"
  }

  setup do
    # Mock the Dify API using Req.Test plug
    test_pid = self()

    Application.put_env(:glific, :dify_req_plug, {Req.Test, test_pid})
    Application.put_env(:glific, :dify_api_key, "test-api-key")

    on_exit(fn ->
      Application.delete_env(:glific, :dify_req_plug)
      Application.delete_env(:glific, :dify_api_key)
    end)

    user =
      Glific.Fixtures.user_fixture(%{
        name: "AskMe Test User",
        roles: ["staff"]
      })

    %{user: user}
  end

  describe "askme/2" do
    test "returns answer and conversation_id on success", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, @dify_success_response)
      end)

      params = %{query: "What is Glific?", page_url: "https://glific.org"}

      assert {:ok, result} = AskmeBot.askme(params, user)
      assert result.answer == "Glific is a two-way communication platform."
      assert result.conversation_id == "conv-abc-123"
    end

    test "saves conversation to database on success", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, @dify_success_response)
      end)

      params = %{query: "What is Glific?"}

      assert {:ok, _result} = AskmeBot.askme(params, user)

      conversation = Repo.get_by(Conversation, conversation_id: "conv-abc-123")
      assert conversation != nil
      assert conversation.user_id == user.id
      assert conversation.organization_id == user.organization_id
    end

    test "does not duplicate conversation on follow-up messages", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, @dify_success_response)
      end)

      params = %{query: "What is Glific?"}
      assert {:ok, _} = AskmeBot.askme(params, user)

      # Second message in same conversation
      params2 = %{query: "Tell me more", conversation_id: "conv-abc-123"}
      assert {:ok, _} = AskmeBot.askme(params2, user)

      conversations =
        Conversation
        |> where([c], c.conversation_id == "conv-abc-123" and c.user_id == ^user.id)
        |> Repo.all()

      assert length(conversations) == 1
    end

    test "returns error on API failure", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"code" => "invalid_param", "message" => "Bad request"})
      end)

      params = %{query: "What is Glific?"}

      assert {:error, error} = AskmeBot.askme(params, user)
      assert error =~ "Dify API error"
    end
  end
end
