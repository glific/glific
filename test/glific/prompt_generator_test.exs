defmodule Glific.PromptGeneratorTest do
  use Glific.DataCase
  import Tesla.Mock

  alias Glific.Partners
  alias Glific.PromptGenerator
  alias Glific.PromptGenerator.PromptGenerationRequest
  alias Glific.Repo

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp enable_kaapi(%{organization_id: org_id}) do
    {:ok, credential} =
      Partners.create_credential(%{
        organization_id: org_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"}
      })

    {:ok, _credential} =
      Partners.update_credential(credential, %{
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"},
        is_active: true,
        organization_id: org_id,
        shortcode: "kaapi"
      })

    :ok
  end

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

  # ---------------------------------------------------------------------------
  # format_answers/1
  # ---------------------------------------------------------------------------

  describe "format_answers/1" do
    test "includes all non-blank answers" do
      result = PromptGenerator.format_answers(@valid_answers)

      assert String.contains?(result, "Organization Name: Pratham Education")
      assert String.contains?(result, "Purpose / Mission: Help children learn")
      assert String.contains?(result, "Target Audience: Children aged 6-14")
      assert String.contains?(result, "Language Policy: Hindi and English")
      assert String.contains?(result, "Tone: Friendly and encouraging")
      assert String.contains?(result, "Response Format: Short messages under 160 characters")
      assert String.contains?(result, "Off-Limits Topics: Politics, religion, violence")
      assert String.contains?(result, "Fallback Message: I don't understand")
      assert String.contains?(result, "Escalation Path: Reply AGENT")
    end

    test "omits blank/nil/empty answers" do
      answers = %{name: "NGO", purpose: "", audience: nil, language: "English"}
      result = PromptGenerator.format_answers(answers)

      assert String.contains?(result, "Organization Name: NGO")
      assert String.contains?(result, "Language Policy: English")
      refute String.contains?(result, "Purpose / Mission")
      refute String.contains?(result, "Target Audience")
    end

    test "omits whitespace-only answers" do
      answers = %{name: "NGO", purpose: "   "}
      result = PromptGenerator.format_answers(answers)

      assert String.contains?(result, "Organization Name: NGO")
      refute String.contains?(result, "Purpose / Mission")
    end

    test "clamps field values to 2000 chars" do
      long_value = String.duplicate("x", 3_000)
      answers = %{name: long_value}
      result = PromptGenerator.format_answers(answers)

      # The label + ": " prefix, then exactly 2000 chars, then "\n"
      [_label, rest] = String.split(result, ": ", parts: 2)
      value = String.trim_trailing(rest)
      assert String.length(value) == 2_000
    end

    test "accepts string-keyed maps" do
      answers = %{"name" => "StringNGO", "purpose" => "Testing"}
      result = PromptGenerator.format_answers(answers)

      assert String.contains?(result, "Organization Name: StringNGO")
      assert String.contains?(result, "Purpose / Mission: Testing")
    end

    test "returns empty string when all answers are blank" do
      assert "" == PromptGenerator.format_answers(%{})
    end
  end

  # ---------------------------------------------------------------------------
  # build_llm_payload/3
  # ---------------------------------------------------------------------------

  describe "build_llm_payload/3" do
    test "contains the meta-prompt as instructions" do
      payload =
        PromptGenerator.build_llm_payload(@valid_answers, "https://cb.example.com", "req-1")

      instructions = get_in(payload, [:config, :blob, :completion, :params, :instructions])
      assert is_binary(instructions)
      assert String.contains?(instructions, "expert prompt engineer")
    end

    test "type is 'text'" do
      payload =
        PromptGenerator.build_llm_payload(@valid_answers, "https://cb.example.com", "req-1")

      type = get_in(payload, [:config, :blob, :completion, :type])
      assert type == "text"
    end

    test "provider is 'openai'" do
      payload =
        PromptGenerator.build_llm_payload(@valid_answers, "https://cb.example.com", "req-1")

      provider = get_in(payload, [:config, :blob, :completion, :provider])
      assert provider == "openai"
    end

    test "model is 'gpt-4o'" do
      payload =
        PromptGenerator.build_llm_payload(@valid_answers, "https://cb.example.com", "req-1")

      model = get_in(payload, [:config, :blob, :completion, :params, :model])
      assert model == "gpt-4o"
    end

    test "temperature is 0.7" do
      payload =
        PromptGenerator.build_llm_payload(@valid_answers, "https://cb.example.com", "req-1")

      temperature = get_in(payload, [:config, :blob, :completion, :params, :temperature])
      assert temperature == 0.7
    end

    test "embeds callback_url and request_id" do
      payload =
        PromptGenerator.build_llm_payload(
          @valid_answers,
          "https://cb.example.com/hook",
          "uuid-42"
        )

      assert payload[:callback_url] == "https://cb.example.com/hook"
      assert payload[:request_metadata][:request_id] == "uuid-42"
    end

    test "query.input contains formatted answers" do
      payload = PromptGenerator.build_llm_payload(@valid_answers, "https://cb.example.com", "r")

      input = get_in(payload, [:query, :input])
      assert String.contains?(input, "Organization Name: Pratham Education")
    end

    test "blank answers are omitted from query.input" do
      answers = %{name: "NGO", purpose: ""}
      payload = PromptGenerator.build_llm_payload(answers, "https://cb.example.com", "r")

      input = get_in(payload, [:query, :input])
      refute String.contains?(input, "Purpose / Mission")
    end
  end

  # ---------------------------------------------------------------------------
  # generate_prompt/3
  # ---------------------------------------------------------------------------

  describe "generate_prompt/3" do
    setup :enable_kaapi

    test "happy path: persists :in_progress row with kaapi_job_id",
         %{organization_id: org_id} do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{data: %{job_id: "job_pg_123"}, success: true}
        }
      end)

      assert {:ok, %PromptGenerationRequest{} = request} =
               PromptGenerator.generate_prompt(@valid_answers, org_id)

      assert request.status == :in_progress
      assert request.kaapi_job_id == "job_pg_123"
      assert request.organization_id == org_id
      # Atom-keyed map is preserved in the struct returned by Repo.insert/1
      assert request.inputs[:name] == "Pratham Education"
    end

    test "persists user_id when provided", %{organization_id: org_id} do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{data: %{job_id: "job_pg_user"}, success: true}
        }
      end)

      assert {:ok, request} = PromptGenerator.generate_prompt(@valid_answers, org_id, 1)
      assert request.user_id == 1
    end

    test "returns error (no row leaked) when Kaapi is inactive", %{organization_id: org_id} do
      # Disable Kaapi by setting is_active: false, then bust the cache
      {:ok, credential} =
        Partners.get_credential(%{organization_id: org_id, shortcode: "kaapi"})

      Partners.update_credential(credential, %{
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"},
        is_active: false,
        organization_id: org_id,
        shortcode: "kaapi"
      })

      # Bust the org cache so fetch_kaapi_creds sees the updated credential state
      org = Partners.get_organization!(org_id)
      Partners.fill_cache(org)

      count_before = Repo.aggregate(PromptGenerationRequest, :count, skip_organization_id: true)

      result = PromptGenerator.generate_prompt(@valid_answers, org_id)

      assert {:error, _reason} = result

      count_after = Repo.aggregate(PromptGenerationRequest, :count, skip_organization_id: true)
      assert count_before == count_after
    end

    test "returns error (no ready row) when Kaapi returns 500", %{organization_id: org_id} do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 500, body: %{error: "Internal Server Error"}}
      end)

      result = PromptGenerator.generate_prompt(@valid_answers, org_id)

      assert {:error, _reason} = result

      count =
        PromptGenerationRequest
        |> Repo.aggregate(:count, skip_organization_id: true)

      assert count == 0
    end

    test "returns error (no ready row) when Kaapi returns 422", %{organization_id: org_id} do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 422, body: %{error: "Unprocessable entity"}}
      end)

      result = PromptGenerator.generate_prompt(@valid_answers, org_id)

      assert {:error, _reason} = result
    end
  end

  # ---------------------------------------------------------------------------
  # handle_callback/1
  # ---------------------------------------------------------------------------

  describe "handle_callback/1" do
    setup :enable_kaapi

    setup %{organization_id: org_id} do
      {:ok, request} =
        %PromptGenerationRequest{}
        |> PromptGenerationRequest.changeset(%{
          inputs: %{"name" => "Test NGO"},
          status: :in_progress,
          kaapi_job_id: "job_cb_001",
          organization_id: org_id
        })
        |> Repo.insert()

      %{request: request}
    end

    test "SUCCESSFUL callback sets status :ready and generated_prompt",
         %{request: request} do
      params = %{
        "data" => %{
          "job_id" => request.kaapi_job_id,
          "status" => "SUCCESSFUL",
          "text" => "You are a helpful WhatsApp chatbot for Test NGO.",
          "error_message" => nil
        }
      }

      assert {:ok, updated} = PromptGenerator.handle_callback(params)
      assert updated.status == :ready
      assert updated.generated_prompt == "You are a helpful WhatsApp chatbot for Test NGO."
      assert updated.id == request.id
    end

    test "FAILED callback sets status :failed and error_message",
         %{request: request} do
      params = %{
        "data" => %{
          "job_id" => request.kaapi_job_id,
          "status" => "FAILED",
          "text" => nil,
          "error_message" => "LLM rate limit exceeded"
        }
      }

      assert {:ok, updated} = PromptGenerator.handle_callback(params)
      assert updated.status == :failed
      assert updated.error_message == "LLM rate limit exceeded"
    end

    test "non-SUCCESSFUL status (e.g. TIMEOUT) sets status :failed",
         %{request: request} do
      params = %{
        "data" => %{
          "job_id" => request.kaapi_job_id,
          "status" => "TIMEOUT",
          "text" => nil,
          "error_message" => "Job timed out"
        }
      }

      assert {:ok, updated} = PromptGenerator.handle_callback(params)
      assert updated.status == :failed
    end

    test "unknown job_id returns error without crashing" do
      params = %{
        "data" => %{
          "job_id" => "nonexistent_job",
          "status" => "SUCCESSFUL",
          "text" => "some text",
          "error_message" => nil
        }
      }

      assert {:error, reason} = PromptGenerator.handle_callback(params)
      assert String.contains?(reason, "nonexistent_job")
    end

    test "double callback (idempotent): calling twice does not crash",
         %{request: request} do
      params = %{
        "data" => %{
          "job_id" => request.kaapi_job_id,
          "status" => "SUCCESSFUL",
          "text" => "Generated prompt text.",
          "error_message" => nil
        }
      }

      assert {:ok, _first} = PromptGenerator.handle_callback(params)
      assert {:ok, _second} = PromptGenerator.handle_callback(params)
    end
  end
end
