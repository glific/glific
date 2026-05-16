defmodule GlificWeb.Resolvers.AskGlificTest do
  use Glific.DataCase

  import Mock

  alias GlificWeb.Resolvers.AskGlific, as: Resolver

  setup do
    user =
      Glific.Fixtures.user_fixture(%{
        name: "AskGlific Resolver Test User",
        roles: ["staff"]
      })

    %{user: user}
  end

  describe "ask/3" do
    test "echoes request_id in the published payload on success", %{user: user} do
      test_pid = self()

      with_mocks([
        {Glific.AskGlific, [],
         [
           ask: fn _params, _user ->
             {:ok,
              %{
                answer: "Hi there",
                conversation_id: "conv-xyz",
                conversation_name: "Test Chat",
                message_id: "msg-1"
              }}
           end
         ]},
        {Absinthe.Subscription, [],
         [
           publish: fn _endpoint, payload, opts ->
             send(test_pid, {:published, payload, opts})
             :ok
           end
         ]}
      ]) do
        params = %{
          input: %{query: "Hi", request_id: "req-abc-123", conversation_id: "conv-xyz"}
        }

        context = %{context: %{current_user: user}}

        assert {:ok, %{answer: nil, conversation_id: nil}} = Resolver.ask(nil, params, context)

        assert_receive {:published, payload, [{:ask_glific_response, topic}]}, 1000
        assert payload.request_id == "req-abc-123"
        assert payload.answer == "Hi there"
        assert payload.conversation_id == "conv-xyz"
        assert topic == "#{user.organization_id}:#{user.id}"
      end
    end

    test "echoes request_id in the published payload on error", %{user: user} do
      test_pid = self()

      with_mocks([
        {Glific.AskGlific, [], [ask: fn _params, _user -> {:error, "Dify boom"} end]},
        {Absinthe.Subscription, [],
         [
           publish: fn _endpoint, payload, opts ->
             send(test_pid, {:published, payload, opts})
             :ok
           end
         ]}
      ]) do
        params = %{input: %{query: "Hi", request_id: "req-error-id"}}
        context = %{context: %{current_user: user}}

        assert {:ok, _sync_result} = Resolver.ask(nil, params, context)

        assert_receive {:published, payload, _opts}, 1000
        assert payload.request_id == "req-error-id"
        assert [%{message: "Dify boom"} | _] = payload.errors
      end
    end

    test "publishes with request_id as nil when not provided", %{user: user} do
      test_pid = self()

      with_mocks([
        {Glific.AskGlific, [],
         [
           ask: fn _params, _user ->
             {:ok, %{answer: "Hi", conversation_id: "conv-1", message_id: "m1"}}
           end
         ]},
        {Absinthe.Subscription, [],
         [
           publish: fn _endpoint, payload, opts ->
             send(test_pid, {:published, payload, opts})
             :ok
           end
         ]}
      ]) do
        params = %{input: %{query: "Hi"}}
        context = %{context: %{current_user: user}}

        assert {:ok, _} = Resolver.ask(nil, params, context)

        assert_receive {:published, payload, _opts}, 1000
        assert payload.request_id == nil
      end
    end
  end
end
