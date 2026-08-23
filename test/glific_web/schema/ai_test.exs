defmodule GlificWeb.Schema.AITest do
  @moduledoc """
  GraphQL integration tests for the AI agent runtime surface:
  - startAiRequest / resolveAiRequest / cancelAiRequest mutations
  - aiConversation / aiConversations / aiMessages queries
  - the ai_request_event subscription's organization_id guard
  - authorization and feature-flag enforcement
  """

  use GlificWeb.ConnCase
  use Wormwood.GQLCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{AI, AI.StepWorker, Fixtures, Repo}
  alias GlificWeb.Schema.AITypes

  load_gql(:start, GlificWeb.Schema, "assets/gql/ai/start_ai_request.gql")
  load_gql(:resolve, GlificWeb.Schema, "assets/gql/ai/resolve_ai_request.gql")
  load_gql(:cancel, GlificWeb.Schema, "assets/gql/ai/cancel_ai_request.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/ai/by_id.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/ai/list.gql")
  load_gql(:messages, GlificWeb.Schema, "assets/gql/ai/messages.gql")

  defp enable_ai_runtime(%{organization_id: organization_id}) do
    FunWithFlags.enable(:is_ai_runtime_enabled, for_actor: %{organization_id: organization_id})
    :ok
  end

  defp future_time,
    do: DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.truncate(:second)

  defp past_time,
    do: DateTime.utc_now() |> DateTime.add(-300, :second) |> DateTime.truncate(:second)

  # ---------------------------------------------------------------------------
  # startAiRequest mutation
  # ---------------------------------------------------------------------------

  describe "startAiRequest mutation" do
    setup :enable_ai_runtime

    test "staff user starts a request for a registered skill and gets a queued ack", %{
      staff: user
    } do
      result =
        auth_query_gql_by(:start, user,
          variables: %{
            "input" => %{"skill" => "echo", "input" => Jason.encode!(%{"message" => "hi"})}
          }
        )

      assert {:ok, query_data} = result
      ack = get_in(query_data, [:data, "startAiRequest"])

      assert ack["status"] == "queued"
      assert ack["requestId"] != nil
      assert ack["conversationId"] != nil
      assert ack["errors"] in [nil, []]

      conversation = Repo.get!(AI.Conversation, ack["conversationId"])
      assert conversation.active_status == :queued
      assert conversation.active_request_id == ack["requestId"]
      assert conversation.skill == "echo"
    end

    test "continuing an existing conversation under the same skill succeeds", %{
      staff: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          user_id: user.id,
          organization_id: organization_id,
          skill: "echo"
        })

      result =
        auth_query_gql_by(:start, user,
          variables: %{
            "input" => %{
              "skill" => "echo",
              "conversationId" => conversation.id,
              "input" => Jason.encode!(%{"message" => "hi again"})
            }
          }
        )

      assert {:ok, query_data} = result
      ack = get_in(query_data, [:data, "startAiRequest"])
      assert ack["conversationId"] == to_string(conversation.id)
      assert ack["status"] == "queued"
    end

    test "rejects continuing a conversation created under a different skill", %{
      staff: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          user_id: user.id,
          organization_id: organization_id,
          skill: "some_other_skill"
        })

      result =
        auth_query_gql_by(:start, user,
          variables: %{
            "input" => %{
              "skill" => "echo",
              "conversationId" => conversation.id,
              "input" => Jason.encode!(%{"message" => "hi"})
            }
          }
        )

      assert {:ok, query_data} = result
      ack = get_in(query_data, [:data, "startAiRequest"])
      assert [%{"key" => "conversation_id"}] = ack["errors"]
    end

    # A skill's feature_flag/0 was declared on the behaviour from the start but read by nothing,
    # so a skill could be started on an org that had never enabled it. Both entry points now go
    # through Glific.AI.Skill.enabled?/2; this covers the durable one.
    test "rejects a skill whose feature flag is off for the organization", %{
      manager: user,
      organization_id: organization_id
    } do
      FunWithFlags.disable(:is_ask_glific_enabled, for_actor: %{organization_id: organization_id})

      result =
        auth_query_gql_by(:start, user,
          variables: %{
            "input" => %{
              "skill" => "ask_glific",
              "input" => Jason.encode!(%{"message" => "why is this contact stuck?"})
            }
          }
        )

      assert {:ok, query_data} = result
      ack = get_in(query_data, [:data, "startAiRequest"])
      assert [%{"key" => "skill", "message" => message}] = ack["errors"]
      assert message =~ "not enabled"
    end

    test "rejects an unknown skill", %{staff: user} do
      result =
        auth_query_gql_by(:start, user,
          variables: %{
            "input" => %{"skill" => "does_not_exist", "input" => Jason.encode!(%{})}
          }
        )

      assert {:ok, query_data} = result
      ack = get_in(query_data, [:data, "startAiRequest"])
      assert [%{"key" => "skill"}] = ack["errors"]
    end

    test "rejects starting a request when one is already in progress", %{
      staff: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          user_id: user.id,
          organization_id: organization_id,
          skill: "echo",
          active_request_id: "already-running",
          active_status: :running
        })

      result =
        auth_query_gql_by(:start, user,
          variables: %{
            "input" => %{
              "skill" => "echo",
              "conversationId" => conversation.id,
              "input" => Jason.encode!(%{"message" => "hi"})
            }
          }
        )

      assert {:ok, query_data} = result
      ack = get_in(query_data, [:data, "startAiRequest"])
      assert [%{"key" => "conversation_id"}] = ack["errors"]
    end

    test "rejects input the skill's validate_input/1 refuses", %{staff: user} do
      result =
        auth_query_gql_by(:start, user,
          variables: %{
            "input" => %{"skill" => "echo", "input" => Jason.encode!(%{"message" => ""})}
          }
        )

      assert {:ok, query_data} = result
      ack = get_in(query_data, [:data, "startAiRequest"])
      assert [%{"key" => "input"}] = ack["errors"]
    end

    test "is rejected when the :is_ai_runtime_enabled flag is off for the org", %{
      staff: user,
      organization_id: organization_id
    } do
      FunWithFlags.disable(:is_ai_runtime_enabled, for_actor: %{organization_id: organization_id})

      result =
        auth_query_gql_by(:start, user,
          variables: %{
            "input" => %{"skill" => "echo", "input" => Jason.encode!(%{"message" => "hi"})}
          }
        )

      assert {:ok, query_data} = result
      message = get_in(query_data, [:errors, Access.at(0), :message])
      assert message =~ "not enabled"
    end

    test "user with no authorized role is rejected", %{staff: user} do
      no_role_user = %{user | roles: []}

      result =
        auth_query_gql_by(:start, no_role_user,
          variables: %{
            "input" => %{"skill" => "echo", "input" => Jason.encode!(%{"message" => "hi"})}
          }
        )

      assert {:ok, query_data} = result
      errors = get_in(query_data, [:errors])
      assert errors != nil
      assert length(errors) > 0
    end
  end

  # ---------------------------------------------------------------------------
  # resolveAiRequest mutation
  # ---------------------------------------------------------------------------

  describe "resolveAiRequest mutation" do
    setup :enable_ai_runtime

    defp gated_conversation(user, organization_id, attrs \\ %{}) do
      Fixtures.ai_conversation_fixture(
        Map.merge(
          %{
            user_id: user.id,
            organization_id: organization_id,
            skill: "echo",
            active_request_id: "req-gate-1",
            active_status: :awaiting_confirmation,
            gate_token: "correct-token",
            gate_expires_at: future_time()
          },
          attrs
        )
      )
    end

    test "accepts a matching, unexpired gate token", %{
      staff: user,
      organization_id: organization_id
    } do
      conversation = gated_conversation(user, organization_id)

      result =
        auth_query_gql_by(:resolve, user,
          variables: %{
            "conversationId" => conversation.id,
            "gateToken" => "correct-token",
            "decision" => "accepted"
          }
        )

      assert {:ok, query_data} = result
      ack = get_in(query_data, [:data, "resolveAiRequest"])
      assert ack["status"] == "running"
      assert ack["requestId"] == "req-gate-1"
      assert ack["errors"] in [nil, []]

      updated = Repo.get!(AI.Conversation, conversation.id)
      assert updated.active_status == :running
      assert updated.gate_token == nil
      assert updated.gate_expires_at == nil

      # The bug this closes: resolving a gate used to ack "running" and then never actually
      # drive the run forward. A resume job must land in the queue, carrying the decision.
      assert [job] = all_enqueued(worker: StepWorker, prefix: "global")
      assert job.args["conversation_id"] == conversation.id
      assert job.args["decision"] == "accepted"
    end

    test "enqueues a resume job carrying a rejected decision", %{
      staff: user,
      organization_id: organization_id
    } do
      conversation = gated_conversation(user, organization_id)

      result =
        auth_query_gql_by(:resolve, user,
          variables: %{
            "conversationId" => conversation.id,
            "gateToken" => "correct-token",
            "decision" => "rejected"
          }
        )

      assert {:ok, query_data} = result
      ack = get_in(query_data, [:data, "resolveAiRequest"])
      assert ack["status"] == "running"

      assert [job] = all_enqueued(worker: StepWorker, prefix: "global")
      assert job.args["conversation_id"] == conversation.id
      assert job.args["decision"] == "rejected"
    end

    test "rejects a wrong gate token and leaves the gate untouched", %{
      staff: user,
      organization_id: organization_id
    } do
      conversation = gated_conversation(user, organization_id)

      result =
        auth_query_gql_by(:resolve, user,
          variables: %{
            "conversationId" => conversation.id,
            "gateToken" => "wrong-token",
            "decision" => "accepted"
          }
        )

      assert {:ok, query_data} = result
      ack = get_in(query_data, [:data, "resolveAiRequest"])
      assert [%{"key" => "gate_token"}] = ack["errors"]

      unchanged = Repo.get!(AI.Conversation, conversation.id)
      assert unchanged.active_status == :awaiting_confirmation
      assert unchanged.gate_token == "correct-token"
    end

    test "rejects an expired gate token even when it matches", %{
      staff: user,
      organization_id: organization_id
    } do
      conversation = gated_conversation(user, organization_id, %{gate_expires_at: past_time()})

      result =
        auth_query_gql_by(:resolve, user,
          variables: %{
            "conversationId" => conversation.id,
            "gateToken" => "correct-token",
            "decision" => "accepted"
          }
        )

      assert {:ok, query_data} = result
      ack = get_in(query_data, [:data, "resolveAiRequest"])
      assert [%{"key" => "gate_token"}] = ack["errors"]

      unchanged = Repo.get!(AI.Conversation, conversation.id)
      assert unchanged.active_status == :awaiting_confirmation
    end

    test "rejects when no confirmation is pending", %{
      staff: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          user_id: user.id,
          organization_id: organization_id,
          skill: "echo"
        })

      result =
        auth_query_gql_by(:resolve, user,
          variables: %{
            "conversationId" => conversation.id,
            "gateToken" => "anything",
            "decision" => "accepted"
          }
        )

      assert {:ok, query_data} = result
      ack = get_in(query_data, [:data, "resolveAiRequest"])
      assert [%{"key" => "gate_token"}] = ack["errors"]
    end

    test "rejects an invalid decision value", %{staff: user, organization_id: organization_id} do
      conversation = gated_conversation(user, organization_id)

      result =
        auth_query_gql_by(:resolve, user,
          variables: %{
            "conversationId" => conversation.id,
            "gateToken" => "correct-token",
            "decision" => "maybe"
          }
        )

      assert {:ok, query_data} = result
      ack = get_in(query_data, [:data, "resolveAiRequest"])
      assert [%{"key" => "decision"}] = ack["errors"]
    end

    test "is rejected when the :is_ai_runtime_enabled flag is off for the org", %{
      staff: user,
      organization_id: organization_id
    } do
      conversation = gated_conversation(user, organization_id)
      FunWithFlags.disable(:is_ai_runtime_enabled, for_actor: %{organization_id: organization_id})

      result =
        auth_query_gql_by(:resolve, user,
          variables: %{
            "conversationId" => conversation.id,
            "gateToken" => "correct-token",
            "decision" => "accepted"
          }
        )

      assert {:ok, query_data} = result
      message = get_in(query_data, [:errors, Access.at(0), :message])
      assert message =~ "not enabled"
    end

    test "user with no authorized role is rejected", %{
      staff: user,
      organization_id: organization_id
    } do
      conversation = gated_conversation(user, organization_id)
      no_role_user = %{user | roles: []}

      result =
        auth_query_gql_by(:resolve, no_role_user,
          variables: %{
            "conversationId" => conversation.id,
            "gateToken" => "correct-token",
            "decision" => "accepted"
          }
        )

      assert {:ok, query_data} = result
      errors = get_in(query_data, [:errors])
      assert errors != nil
      assert length(errors) > 0
    end
  end

  # ---------------------------------------------------------------------------
  # cancelAiRequest mutation
  # ---------------------------------------------------------------------------

  describe "cancelAiRequest mutation" do
    setup :enable_ai_runtime

    test "cancels an in-flight request", %{staff: user, organization_id: organization_id} do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          user_id: user.id,
          organization_id: organization_id,
          skill: "echo",
          active_request_id: "req-cancel-1",
          active_status: :running
        })

      result =
        auth_query_gql_by(:cancel, user, variables: %{"conversationId" => conversation.id})

      assert {:ok, query_data} = result
      ack = get_in(query_data, [:data, "cancelAiRequest"])
      assert ack["status"] == "cancelled"
      assert ack["requestId"] == "req-cancel-1"

      updated = Repo.get!(AI.Conversation, conversation.id)
      assert updated.active_status == :cancelled
    end

    test "is a no-op, not an error, when nothing is in flight", %{
      staff: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          user_id: user.id,
          organization_id: organization_id,
          skill: "echo"
        })

      result =
        auth_query_gql_by(:cancel, user, variables: %{"conversationId" => conversation.id})

      assert {:ok, query_data} = result
      ack = get_in(query_data, [:data, "cancelAiRequest"])
      assert ack["status"] == "idle"
      assert ack["errors"] in [nil, []]
    end

    test "is rejected when the :is_ai_runtime_enabled flag is off for the org", %{
      staff: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          user_id: user.id,
          organization_id: organization_id,
          skill: "echo"
        })

      FunWithFlags.disable(:is_ai_runtime_enabled, for_actor: %{organization_id: organization_id})

      result =
        auth_query_gql_by(:cancel, user, variables: %{"conversationId" => conversation.id})

      assert {:ok, query_data} = result
      message = get_in(query_data, [:errors, Access.at(0), :message])
      assert message =~ "not enabled"
    end

    test "user with no authorized role is rejected", %{
      staff: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          user_id: user.id,
          organization_id: organization_id,
          skill: "echo"
        })

      no_role_user = %{user | roles: []}

      result =
        auth_query_gql_by(:cancel, no_role_user,
          variables: %{"conversationId" => conversation.id}
        )

      assert {:ok, query_data} = result
      errors = get_in(query_data, [:errors])
      assert errors != nil
      assert length(errors) > 0
    end
  end

  # ---------------------------------------------------------------------------
  # aiConversation / aiConversations / aiMessages queries
  # ---------------------------------------------------------------------------

  describe "AI conversation/message queries" do
    test "aiConversation returns a conversation owned by the caller", %{
      staff: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          user_id: user.id,
          organization_id: organization_id,
          skill: "echo"
        })

      result = auth_query_gql_by(:by_id, user, variables: %{"id" => conversation.id})

      assert {:ok, query_data} = result
      returned = get_in(query_data, [:data, "aiConversation", "conversation"])
      assert returned["id"] == to_string(conversation.id)
      assert returned["skill"] == "echo"
    end

    test "aiConversation does not leak another user's conversation", %{
      staff: user,
      organization_id: organization_id
    } do
      other_user = Fixtures.user_fixture(%{roles: ["staff"], organization_id: organization_id})

      conversation =
        Fixtures.ai_conversation_fixture(%{
          user_id: other_user.id,
          organization_id: organization_id,
          skill: "echo"
        })

      result = auth_query_gql_by(:by_id, user, variables: %{"id" => conversation.id})

      assert {:ok, query_data} = result
      assert get_in(query_data, [:data, "aiConversation", "conversation"]) == nil
    end

    test "aiConversations lists only the caller's conversations", %{
      staff: user,
      organization_id: organization_id
    } do
      other_user = Fixtures.user_fixture(%{roles: ["staff"], organization_id: organization_id})

      mine =
        Fixtures.ai_conversation_fixture(%{
          user_id: user.id,
          organization_id: organization_id,
          skill: "echo"
        })

      Fixtures.ai_conversation_fixture(%{
        user_id: other_user.id,
        organization_id: organization_id,
        skill: "echo"
      })

      result = auth_query_gql_by(:list, user, variables: %{})

      assert {:ok, query_data} = result
      ids = get_in(query_data, [:data, "aiConversations"]) |> Enum.map(& &1["id"])
      assert ids == [to_string(mine.id)]
    end

    test "aiMessages lists a conversation's messages in seq order", %{
      staff: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          user_id: user.id,
          organization_id: organization_id,
          skill: "echo"
        })

      Fixtures.ai_message_fixture(%{conversation: conversation, seq: 2})
      Fixtures.ai_message_fixture(%{conversation: conversation, seq: 1})

      result =
        auth_query_gql_by(:messages, user, variables: %{"conversationId" => conversation.id})

      assert {:ok, query_data} = result
      seqs = get_in(query_data, [:data, "aiMessages"]) |> Enum.map(& &1["seq"])
      assert seqs == [1, 2]
    end

    test "aiMessages rejects access to another user's conversation", %{
      staff: user,
      organization_id: organization_id
    } do
      other_user = Fixtures.user_fixture(%{roles: ["staff"], organization_id: organization_id})

      conversation =
        Fixtures.ai_conversation_fixture(%{
          user_id: other_user.id,
          organization_id: organization_id,
          skill: "echo"
        })

      result =
        auth_query_gql_by(:messages, user, variables: %{"conversationId" => conversation.id})

      assert {:ok, query_data} = result
      assert get_in(query_data, [:data, "aiMessages"]) == nil
      assert get_in(query_data, [:errors]) != nil
    end
  end

  # ---------------------------------------------------------------------------
  # ai_request_event subscription config
  # ---------------------------------------------------------------------------

  describe "ai_request_event subscription config" do
    test "accepts when organization_id matches the caller's organization", %{
      organization_id: organization_id
    } do
      user = Fixtures.user_fixture(%{organization_id: organization_id})

      assert {:ok, [topic: topic]} =
               AITypes.subscription_topic(%{organization_id: to_string(organization_id)}, %{
                 context: %{current_user: user}
               })

      assert topic == "#{organization_id}:#{user.id}"
    end

    test "rejects a mismatched organization_id", %{organization_id: organization_id} do
      user = Fixtures.user_fixture(%{organization_id: organization_id})

      assert {:error, _reason} =
               AITypes.subscription_topic(%{organization_id: "999999"}, %{
                 context: %{current_user: user}
               })
    end
  end
end
