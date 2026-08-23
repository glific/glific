defmodule Glific.PromptGeneratorTest do
  # Glific.AI.Model.Stub is a globally-named Agent shared across test files — async: true
  # would leak one file's queued responses into another's assertions.
  use Glific.DataCase, async: false

  alias Glific.AI.Model.Stub
  alias Glific.Fixtures
  alias Glific.PromptGenerator
  alias Glific.PromptGenerator.PromptGenerationRequest
  alias Glific.Repo

  @valid_answers %{
    name: "Pratham Education",
    purpose: "Help children learn basic reading and maths",
    audience: "Children aged 6-14 in rural India",
    language: "Hindi and English",
    tone: "Friendly and encouraging",
    format: "Short messages under 160 characters",
    off_limits: "Politics, religion, violence",
    fallback: "I don't understand. Please type 'Help' for options.",
    escalation: "Reply AGENT to speak with a human"
  }

  # Glific.AI.Run.sync/3 honours the skill's own feature_flag/0, and every flag is seeded
  # disabled for a new organisation (Glific.Misc.Flags), so this precondition is what the whole
  # generate_prompt/3 describe block depends on rather than something incidental.
  setup %{organization_id: organization_id} do
    start_supervised!(Stub)

    FunWithFlags.enable(:is_prompt_generator_enabled,
      for_actor: %{organization_id: organization_id}
    )

    user = Fixtures.user_fixture(%{organization_id: organization_id})
    %{user: user}
  end

  # ---------------------------------------------------------------------------
  # format_answers/1
  # ---------------------------------------------------------------------------

  describe "format_answers/1" do
    test "includes all non-blank answers" do
      result = PromptGenerator.format_answers(@valid_answers)

      assert String.contains?(result, "- persona: Pratham Education")
      assert String.contains?(result, "- objective: Help children learn")
      assert String.contains?(result, "- audience: Children aged 6-14")
      assert String.contains?(result, "- language: Hindi and English")
      assert String.contains?(result, "- tone: Friendly and encouraging")
      assert String.contains?(result, "- length: Short messages under 160 characters")
      assert String.contains?(result, "- skip_answer_topics: Politics, religion, violence")
      assert String.contains?(result, "- fallback_answer: I don't understand")
      assert String.contains?(result, "- escalation_details: Reply AGENT")
    end

    test "omits blank/nil/empty answers" do
      answers = %{name: "NGO", purpose: "", audience: nil, language: "English"}
      result = PromptGenerator.format_answers(answers)

      assert String.contains?(result, "- persona: NGO")
      assert String.contains?(result, "- language: English")
      refute String.contains?(result, "objective")
      refute String.contains?(result, "audience")
    end

    test "omits whitespace-only answers" do
      answers = %{name: "NGO", purpose: "   "}
      result = PromptGenerator.format_answers(answers)

      assert String.contains?(result, "- persona: NGO")
      refute String.contains?(result, "objective")
    end

    test "formats long values as-is (oversized fields are rejected at the resolver, not clamped)" do
      long_value = String.duplicate("x", 3_000)
      result = PromptGenerator.format_answers(%{name: long_value})

      assert String.contains?(result, "- persona: #{long_value}")
    end

    test "accepts string-keyed maps" do
      answers = %{"name" => "StringNGO", "purpose" => "Testing"}
      result = PromptGenerator.format_answers(answers)

      assert String.contains?(result, "- persona: StringNGO")
      assert String.contains?(result, "- objective: Testing")
    end

    test "returns empty string when all answers are blank" do
      assert "" == PromptGenerator.format_answers(%{})
    end
  end

  # ---------------------------------------------------------------------------
  # generate_prompt/3
  # ---------------------------------------------------------------------------

  describe "generate_prompt/3 — happy path" do
    test "persists a :ready row with the generated prompt", %{
      organization_id: org_id,
      user: user
    } do
      Stub.queue_text("draft")

      Stub.queue_object(%{
        "generated_prompt" => "You are a helpful WhatsApp chatbot for Pratham Education."
      })

      assert {:ok, %PromptGenerationRequest{} = request} =
               PromptGenerator.generate_prompt(@valid_answers, org_id, user.id)

      assert request.status == :ready

      assert request.generated_prompt ==
               "You are a helpful WhatsApp chatbot for Pratham Education."

      assert request.organization_id == org_id
      assert request.user_id == user.id
      assert is_binary(request.request_id)
      assert byte_size(request.request_id) > 0
      # Atom-keyed map is preserved in the struct returned by Repo.insert/1
      assert request.inputs[:name] == "Pratham Education"
    end

    test "sends the formatted answers as the skill's message input", %{
      organization_id: org_id,
      user: user
    } do
      Stub.queue_text("draft")
      Stub.queue_object(%{"generated_prompt" => "Some generated prompt."})

      assert {:ok, _request} = PromptGenerator.generate_prompt(@valid_answers, org_id, user.id)

      [first_call | _rest] = Stub.calls()
      user_message = Enum.find(first_call.messages, &(&1.role == :user))
      text = user_message.content |> Enum.map_join("", & &1.text)

      assert text == PromptGenerator.format_answers(@valid_answers)
    end
  end

  describe "generate_prompt/3 — failure paths" do
    test "persists a :failed row when the model call errors", %{
      organization_id: org_id,
      user: user
    } do
      Stub.queue_error(:timeout)

      assert {:ok, %PromptGenerationRequest{} = request} =
               PromptGenerator.generate_prompt(@valid_answers, org_id, user.id)

      assert request.status == :failed
      assert is_binary(request.error_message)
      assert is_nil(request.generated_prompt)
    end

    test "persists a :failed row when the skill's feature flag is disabled for the org", %{
      organization_id: org_id,
      user: user
    } do
      FunWithFlags.disable(:is_prompt_generator_enabled, for_actor: %{organization_id: org_id})

      assert {:ok, %PromptGenerationRequest{} = request} =
               PromptGenerator.generate_prompt(@valid_answers, org_id, user.id)

      assert request.status == :failed
      assert is_binary(request.error_message)
    end

    test "returns an error without inserting a row when user_id is nil", %{
      organization_id: org_id
    } do
      count_before = Repo.aggregate(PromptGenerationRequest, :count, skip_organization_id: true)

      assert {:error, _reason} = PromptGenerator.generate_prompt(@valid_answers, org_id)

      count_after = Repo.aggregate(PromptGenerationRequest, :count, skip_organization_id: true)
      assert count_before == count_after
    end

    test "returns an error without inserting a row when user_id belongs to another organization",
         %{organization_id: org_id} do
      other_organization = Fixtures.organization_fixture()
      other_user = Fixtures.user_fixture(%{organization_id: other_organization.id})

      count_before = Repo.aggregate(PromptGenerationRequest, :count, skip_organization_id: true)

      assert {:error, _reason} =
               PromptGenerator.generate_prompt(@valid_answers, org_id, other_user.id)

      count_after = Repo.aggregate(PromptGenerationRequest, :count, skip_organization_id: true)
      assert count_before == count_after
    end
  end

  # ---------------------------------------------------------------------------
  # handle_callback/1 — legacy Kaapi callback shape (kept for the still-wired
  # /kaapi/prompt_generation route; not exercised by generate_prompt/3 anymore)
  # ---------------------------------------------------------------------------

  describe "handle_callback/1" do
    setup %{organization_id: org_id} do
      request_id = Ecto.UUID.generate()

      {:ok, request} =
        %PromptGenerationRequest{}
        |> PromptGenerationRequest.changeset(%{
          inputs: %{"name" => "Test NGO"},
          status: :in_progress,
          request_id: request_id,
          organization_id: org_id
        })
        |> Repo.insert()

      %{request: request, request_id: request_id}
    end

    test "success callback sets status :ready and generated_prompt",
         %{request: request, request_id: request_id} do
      params = %{
        "success" => true,
        "data" => %{
          "response" => %{
            "provider" => "openai-native",
            "model" => "gpt-4o-2024-08-06",
            "output" => %{
              "type" => "text",
              "content" => %{
                "format" => "text",
                "value" => "You are a helpful WhatsApp chatbot for Test NGO."
              }
            }
          },
          "usage" => %{"input_tokens" => 161, "output_tokens" => 76, "total_tokens" => 237}
        },
        "error" => nil,
        "errors" => nil,
        "metadata" => %{
          "request_id" => request_id,
          "warnings" => []
        }
      }

      assert {:ok, updated} = PromptGenerator.handle_callback(params)
      assert updated.status == :ready
      assert updated.generated_prompt == "You are a helpful WhatsApp chatbot for Test NGO."
      assert updated.id == request.id
    end

    test "failure callback (success: false) sets status :failed and error_message",
         %{request_id: request_id} do
      params = %{
        "success" => false,
        "data" => nil,
        "error" => "LLM rate limit exceeded",
        "errors" => nil,
        "metadata" => %{"request_id" => request_id, "warnings" => []}
      }

      assert {:ok, updated} = PromptGenerator.handle_callback(params)
      assert updated.status == :failed
      assert updated.error_message == "LLM rate limit exceeded"
    end

    test "failure callback with errors list sets status :failed",
         %{request_id: request_id} do
      params = %{
        "success" => false,
        "data" => nil,
        "error" => nil,
        "errors" => ["quota exceeded", "upstream timeout"],
        "metadata" => %{"request_id" => request_id, "warnings" => []}
      }

      assert {:ok, updated} = PromptGenerator.handle_callback(params)
      assert updated.status == :failed
      assert is_binary(updated.error_message)
      refute is_nil(updated.error_message)
    end

    test "unknown request_id returns error without crashing" do
      params = %{
        "success" => true,
        "data" => %{
          "response" => %{
            "output" => %{"content" => %{"value" => "some text"}}
          }
        },
        "metadata" => %{"request_id" => "nonexistent-uuid-000", "warnings" => []}
      }

      assert {:error, reason} = PromptGenerator.handle_callback(params)
      assert String.contains?(reason, "nonexistent-uuid-000")
    end

    test "double callback (idempotent): calling twice does not crash",
         %{request_id: request_id} do
      params = %{
        "success" => true,
        "data" => %{
          "response" => %{
            "output" => %{
              "content" => %{"value" => "Generated prompt text."}
            }
          }
        },
        "metadata" => %{"request_id" => request_id, "warnings" => []}
      }

      assert {:ok, _first} = PromptGenerator.handle_callback(params)
      assert {:ok, _second} = PromptGenerator.handle_callback(params)
    end

    test "late failure callback does not clobber an already :ready row",
         %{request_id: request_id} do
      success = %{
        "success" => true,
        "data" => %{
          "response" => %{
            "output" => %{"content" => %{"value" => "The generated prompt."}}
          }
        },
        "metadata" => %{"request_id" => request_id, "warnings" => []}
      }

      late_failure = %{
        "success" => false,
        "data" => nil,
        "error" => "Too late",
        "metadata" => %{"request_id" => request_id, "warnings" => []}
      }

      assert {:ok, ready} = PromptGenerator.handle_callback(success)
      assert ready.status == :ready

      assert {:ok, unchanged} = PromptGenerator.handle_callback(late_failure)
      assert unchanged.status == :ready
      assert unchanged.generated_prompt == "The generated prompt."
      assert is_nil(unchanged.error_message)
    end

    test "late success callback does not clobber an already :failed row",
         %{request_id: request_id} do
      failure = %{
        "success" => false,
        "data" => nil,
        "error" => "Upstream error",
        "metadata" => %{"request_id" => request_id, "warnings" => []}
      }

      late_success = %{
        "success" => true,
        "data" => %{
          "response" => %{
            "output" => %{"content" => %{"value" => "Too late."}}
          }
        },
        "metadata" => %{"request_id" => request_id, "warnings" => []}
      }

      assert {:ok, failed} = PromptGenerator.handle_callback(failure)
      assert failed.status == :failed

      assert {:ok, unchanged} = PromptGenerator.handle_callback(late_success)
      assert unchanged.status == :failed
      assert is_nil(unchanged.generated_prompt)
    end

    test "malformed payload (no metadata.request_id) returns error without crashing" do
      assert {:error, _reason} = PromptGenerator.handle_callback(%{"unexpected" => "shape"})
      assert {:error, _reason} = PromptGenerator.handle_callback(%{})
      assert {:error, _reason} = PromptGenerator.handle_callback(%{"metadata" => %{}})
    end
  end
end
