defmodule Glific.Dify.ApiClientTest do
  use ExUnit.Case

  alias Glific.Dify.ApiClient

  setup do
    test_pid = self()
    Application.put_env(:glific, :dify_req_plug, {Req.Test, test_pid})

    on_exit(fn ->
      Application.delete_env(:glific, :dify_req_plug)
    end)

    :ok
  end

  describe "chat_messages/2" do
    test "returns parsed response on success" do
      Req.Test.stub(self(), fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/chat-messages"

        Req.Test.json(conn, %{
          "answer" => "Hello!",
          "conversation_id" => "conv-123"
        })
      end)

      body = %{
        "query" => "Hi",
        "user" => "org-1",
        "response_mode" => "blocking",
        "conversation_id" => "",
        "inputs" => %{}
      }

      assert {:ok, response} = ApiClient.chat_messages(body)
      assert response["answer"] == "Hello!"
      assert response["conversation_id"] == "conv-123"
    end

    test "returns error on non-2xx status" do
      Req.Test.stub(self(), fn conn ->
        conn
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{"error" => "Rate limited"})
      end)

      assert {:error, error} = ApiClient.chat_messages(%{"query" => "Hi"})
      assert error =~ "Dify API error (429)"
    end
  end

  describe "conversations/4" do
    test "returns parsed response on success" do
      Req.Test.stub(self(), fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/v1/conversations"

        Req.Test.json(conn, %{
          "data" => [%{"id" => "conv-1", "name" => "Chat 1"}],
          "has_more" => false,
          "limit" => 20
        })
      end)

      assert {:ok, response} = ApiClient.conversations("org-1")
      assert length(response["data"]) == 1
    end

    test "passes query params correctly" do
      Req.Test.stub(self(), fn conn ->
        params = conn.params
        assert params["user"] == "org-1"
        assert params["limit"] == "5"
        assert params["last_id"] == "conv-xyz"

        Req.Test.json(conn, %{"data" => [], "has_more" => false, "limit" => 5})
      end)

      assert {:ok, _} = ApiClient.conversations("org-1", 5, "conv-xyz")
    end

    test "returns error on failure" do
      Req.Test.stub(self(), fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"error" => "Internal"})
      end)

      assert {:error, error} = ApiClient.conversations("org-1")
      assert error =~ "Dify API error (500)"
    end
  end

  describe "messages/5" do
    test "returns parsed response on success" do
      Req.Test.stub(self(), fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/v1/messages"

        Req.Test.json(conn, %{
          "data" => [
            %{"id" => "msg-1", "query" => "Q", "answer" => "A", "created_at" => 1_700_000_000}
          ],
          "has_more" => false,
          "limit" => 20
        })
      end)

      assert {:ok, response} = ApiClient.messages("conv-1", "org-1")
      assert length(response["data"]) == 1
    end

    test "passes query params correctly" do
      Req.Test.stub(self(), fn conn ->
        params = conn.params
        assert params["conversation_id"] == "conv-1"
        assert params["user"] == "org-1"
        assert params["limit"] == "10"
        assert params["first_id"] == "msg-050"

        Req.Test.json(conn, %{"data" => [], "has_more" => false, "limit" => 10})
      end)

      assert {:ok, _} = ApiClient.messages("conv-1", "org-1", 10, "msg-050")
    end

    test "returns error on failure" do
      Req.Test.stub(self(), fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"error" => "Not found"})
      end)

      assert {:error, error} = ApiClient.messages("conv-1", "org-1")
      assert error =~ "Dify API error (404)"
    end
  end

  describe "message_feedback/3" do
    test "returns success on valid feedback" do
      Req.Test.stub(self(), fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/messages/msg-123/feedbacks"

        Req.Test.json(conn, %{"result" => "success"})
      end)

      body = %{"rating" => "like", "user" => "org-1", "content" => "Helpful!"}

      assert {:ok, response} = ApiClient.message_feedback("msg-123", body)
      assert response["result"] == "success"
    end

    test "returns error on failure" do
      Req.Test.stub(self(), fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"error" => "Message not found"})
      end)

      body = %{"rating" => "like", "user" => "org-1"}

      assert {:error, error} = ApiClient.message_feedback("msg-999", body)
      assert error =~ "Dify API error (404)"
    end
  end

  describe "auto_generate_conversation_name/3" do
    test "returns name on success" do
      Req.Test.stub(self(), fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/conversations/conv-123/name"

        Req.Test.json(conn, %{"name" => "Auto Generated Name"})
      end)

      assert {:ok, response} =
               ApiClient.auto_generate_conversation_name("conv-123", "org-1")

      assert response["name"] == "Auto Generated Name"
    end

    test "returns error on failure" do
      Req.Test.stub(self(), fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"error" => "Failed"})
      end)

      assert {:error, error} =
               ApiClient.auto_generate_conversation_name("conv-123", "org-1")

      assert error =~ "Dify API error (500)"
    end
  end
end
