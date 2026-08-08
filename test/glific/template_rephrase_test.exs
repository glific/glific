defmodule Glific.TemplateRephraseTest do
  use Glific.DataCase
  import Tesla.Mock

  alias Glific.Partners
  alias Glific.Repo
  alias Glific.TemplateRephrase
  alias Glific.TemplateRephrase.TemplateRephraseRequest

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

  @original_text "Hi {{1}}, your order {{2}} has shipped! Get 20% off your next order now!"

  describe "instructions_for/2" do
    test "professional action returns the professional system prompt" do
      instructions = TemplateRephrase.instructions_for(:professional, nil)

      assert is_binary(instructions)
      assert String.contains?(instructions, "professional")
      assert String.contains?(instructions, "{{1}}")
      assert String.contains?(instructions, "Return only the rewritten message text")
    end

    test "utility action returns the utility system prompt" do
      instructions = TemplateRephrase.instructions_for(:utility, nil)

      assert is_binary(instructions)
      assert String.contains?(instructions, "Utility")
      assert String.contains?(instructions, "promotional")
      assert String.contains?(instructions, "Return only the rewritten message text")
    end

    test "custom action interpolates the user's custom_prompt" do
      instructions = TemplateRephrase.instructions_for(:custom, "Make it sound urgent")

      assert String.contains?(instructions, "Make it sound urgent")
      assert String.contains?(instructions, "{{1}}")
      assert String.contains?(instructions, "Return only the rewritten message text")
    end
  end

  describe "build_llm_payload/5" do
    test "provider is 'openai'" do
      payload =
        TemplateRephrase.build_llm_payload(
          @original_text,
          :professional,
          nil,
          "https://cb.example.com",
          "req-1"
        )

      assert get_in(payload, [:config, :blob, :completion, :provider]) == "openai"
    end

    test "model is 'gpt-4o'" do
      payload =
        TemplateRephrase.build_llm_payload(
          @original_text,
          :professional,
          nil,
          "https://cb.example.com",
          "req-1"
        )

      assert get_in(payload, [:config, :blob, :completion, :params, :model]) == "gpt-4o"
    end

    test "temperature is 0.4" do
      payload =
        TemplateRephrase.build_llm_payload(
          @original_text,
          :professional,
          nil,
          "https://cb.example.com",
          "req-1"
        )

      assert get_in(payload, [:config, :blob, :completion, :params, :temperature]) == 0.4
    end

    test "type is 'text'" do
      payload =
        TemplateRephrase.build_llm_payload(
          @original_text,
          :utility,
          nil,
          "https://cb.example.com",
          "req-1"
        )

      assert get_in(payload, [:config, :blob, :completion, :type]) == "text"
    end

    test "instructions match the professional action prompt" do
      payload =
        TemplateRephrase.build_llm_payload(
          @original_text,
          :professional,
          nil,
          "https://cb.example.com",
          "req-1"
        )

      instructions = get_in(payload, [:config, :blob, :completion, :params, :instructions])
      assert instructions == TemplateRephrase.instructions_for(:professional, nil)
    end

    test "instructions match the utility action prompt" do
      payload =
        TemplateRephrase.build_llm_payload(
          @original_text,
          :utility,
          nil,
          "https://cb.example.com",
          "req-1"
        )

      instructions = get_in(payload, [:config, :blob, :completion, :params, :instructions])
      assert instructions == TemplateRephrase.instructions_for(:utility, nil)
    end

    test "instructions match the custom action prompt with interpolated instruction" do
      payload =
        TemplateRephrase.build_llm_payload(
          @original_text,
          :custom,
          "Make it sound urgent",
          "https://cb.example.com",
          "req-1"
        )

      instructions = get_in(payload, [:config, :blob, :completion, :params, :instructions])
      assert String.contains?(instructions, "Make it sound urgent")
    end

    test "embeds callback_url and request_id" do
      payload =
        TemplateRephrase.build_llm_payload(
          @original_text,
          :professional,
          nil,
          "https://cb.example.com/hook",
          "uuid-42"
        )

      assert payload[:callback_url] == "https://cb.example.com/hook"
      assert payload[:request_metadata][:request_id] == "uuid-42"
    end

    test "query.input is the original template text" do
      payload =
        TemplateRephrase.build_llm_payload(
          @original_text,
          :professional,
          nil,
          "https://cb.example.com",
          "req-1"
        )

      assert get_in(payload, [:query, :input]) == @original_text
    end
  end

  describe "rephrase/3" do
    setup :enable_kaapi

    test "happy path (professional): persists :in_progress row with request_id",
         %{organization_id: org_id} do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 200, body: %{data: %{job_id: "job_tr_123"}, success: true}}
      end)

      assert {:ok, %TemplateRephraseRequest{} = request} =
               TemplateRephrase.rephrase(
                 %{text: @original_text, action: :professional, custom_prompt: nil},
                 org_id
               )

      assert request.status == :in_progress
      assert request.organization_id == org_id
      assert request.action == :professional
      assert request.original_text == @original_text
      assert is_binary(request.request_id)
      assert byte_size(request.request_id) > 0
    end

    test "happy path (utility): persists :in_progress row", %{organization_id: org_id} do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 200, body: %{data: %{job_id: "job_tr_util"}, success: true}}
      end)

      assert {:ok, request} =
               TemplateRephrase.rephrase(
                 %{text: @original_text, action: :utility, custom_prompt: nil},
                 org_id
               )

      assert request.status == :in_progress
      assert request.action == :utility
    end

    test "happy path (custom): persists :in_progress row with custom_prompt",
         %{organization_id: org_id} do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 200, body: %{data: %{job_id: "job_tr_custom"}, success: true}}
      end)

      assert {:ok, request} =
               TemplateRephrase.rephrase(
                 %{text: @original_text, action: :custom, custom_prompt: "Make it urgent"},
                 org_id
               )

      assert request.status == :in_progress
      assert request.action == :custom
      assert request.custom_prompt == "Make it urgent"
    end

    test "persists user_id when provided", %{organization_id: org_id} do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 200, body: %{data: %{job_id: "job_tr_user"}, success: true}}
      end)

      assert {:ok, request} =
               TemplateRephrase.rephrase(
                 %{text: @original_text, action: :professional, custom_prompt: nil},
                 org_id,
                 1
               )

      assert request.user_id == 1
    end

    test "returns error (no row leaked) when Kaapi is inactive", %{organization_id: org_id} do
      {:ok, credential} =
        Partners.get_credential(%{organization_id: org_id, shortcode: "kaapi"})

      Partners.update_credential(credential, %{
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"},
        is_active: false,
        organization_id: org_id,
        shortcode: "kaapi"
      })

      org = Partners.get_organization!(org_id)
      Partners.fill_cache(org)

      count_before = Repo.aggregate(TemplateRephraseRequest, :count, skip_organization_id: true)

      result =
        TemplateRephrase.rephrase(
          %{text: @original_text, action: :professional, custom_prompt: nil},
          org_id
        )

      assert {:error, _reason} = result

      count_after = Repo.aggregate(TemplateRephraseRequest, :count, skip_organization_id: true)
      assert count_before == count_after
    end

    test "returns error (no row) when Kaapi returns 500", %{organization_id: org_id} do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 500, body: %{error: "Internal Server Error"}}
      end)

      result =
        TemplateRephrase.rephrase(
          %{text: @original_text, action: :professional, custom_prompt: nil},
          org_id
        )

      assert {:error, _reason} = result

      count = Repo.aggregate(TemplateRephraseRequest, :count, skip_organization_id: true)
      assert count == 0
    end

    test "returns error (no row) when Kaapi returns 422", %{organization_id: org_id} do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 422, body: %{error: "Unprocessable entity"}}
      end)

      count_before = Repo.aggregate(TemplateRephraseRequest, :count, skip_organization_id: true)

      result =
        TemplateRephrase.rephrase(
          %{text: @original_text, action: :professional, custom_prompt: nil},
          org_id
        )

      assert {:error, _reason} = result

      count_after = Repo.aggregate(TemplateRephraseRequest, :count, skip_organization_id: true)
      assert count_before == count_after
    end
  end

  describe "handle_callback/1" do
    setup :enable_kaapi

    setup %{organization_id: org_id} do
      request_id = Ecto.UUID.generate()

      {:ok, request} =
        %TemplateRephraseRequest{}
        |> TemplateRephraseRequest.changeset(%{
          original_text: @original_text,
          action: :professional,
          status: :in_progress,
          request_id: request_id,
          organization_id: org_id
        })
        |> Repo.insert()

      %{request: request, request_id: request_id}
    end

    test "success callback sets status :ready and rephrased_text",
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
                "value" => "Hello {{1}}, your order {{2}} has shipped."
              }
            }
          },
          "usage" => %{"input_tokens" => 100, "output_tokens" => 40, "total_tokens" => 140}
        },
        "error" => nil,
        "errors" => nil,
        "metadata" => %{"request_id" => request_id, "warnings" => []}
      }

      assert {:ok, updated} = TemplateRephrase.handle_callback(params)
      assert updated.status == :ready
      assert updated.rephrased_text == "Hello {{1}}, your order {{2}} has shipped."
      assert updated.id == request.id
    end

    test "failure callback (success: false) with error sets status :failed and error_message",
         %{request_id: request_id} do
      params = %{
        "success" => false,
        "data" => nil,
        "error" => "LLM rate limit exceeded",
        "errors" => nil,
        "metadata" => %{"request_id" => request_id, "warnings" => []}
      }

      assert {:ok, updated} = TemplateRephrase.handle_callback(params)
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

      assert {:ok, updated} = TemplateRephrase.handle_callback(params)
      assert updated.status == :failed
      assert is_binary(updated.error_message)
      refute is_nil(updated.error_message)
    end

    test "unknown request_id returns error without crashing" do
      params = %{
        "success" => true,
        "data" => %{
          "response" => %{"output" => %{"content" => %{"value" => "some text"}}}
        },
        "metadata" => %{"request_id" => "nonexistent-uuid-000", "warnings" => []}
      }

      assert {:error, reason} = TemplateRephrase.handle_callback(params)
      assert String.contains?(reason, "nonexistent-uuid-000")
    end

    test "double callback (idempotent): calling twice does not crash",
         %{request_id: request_id} do
      params = %{
        "success" => true,
        "data" => %{
          "response" => %{"output" => %{"content" => %{"value" => "Rephrased text."}}}
        },
        "metadata" => %{"request_id" => request_id, "warnings" => []}
      }

      assert {:ok, _first} = TemplateRephrase.handle_callback(params)
      assert {:ok, _second} = TemplateRephrase.handle_callback(params)
    end

    test "late failure callback does not clobber an already :ready row",
         %{request_id: request_id} do
      success = %{
        "success" => true,
        "data" => %{
          "response" => %{"output" => %{"content" => %{"value" => "The rephrased text."}}}
        },
        "metadata" => %{"request_id" => request_id, "warnings" => []}
      }

      late_failure = %{
        "success" => false,
        "data" => nil,
        "error" => "Too late",
        "metadata" => %{"request_id" => request_id, "warnings" => []}
      }

      assert {:ok, ready} = TemplateRephrase.handle_callback(success)
      assert ready.status == :ready

      assert {:ok, unchanged} = TemplateRephrase.handle_callback(late_failure)
      assert unchanged.status == :ready
      assert unchanged.rephrased_text == "The rephrased text."
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
          "response" => %{"output" => %{"content" => %{"value" => "Too late."}}}
        },
        "metadata" => %{"request_id" => request_id, "warnings" => []}
      }

      assert {:ok, failed} = TemplateRephrase.handle_callback(failure)
      assert failed.status == :failed

      assert {:ok, unchanged} = TemplateRephrase.handle_callback(late_success)
      assert unchanged.status == :failed
      assert is_nil(unchanged.rephrased_text)
    end

    test "malformed payload (no metadata.request_id) returns error without crashing" do
      assert {:error, _reason} = TemplateRephrase.handle_callback(%{"unexpected" => "shape"})
      assert {:error, _reason} = TemplateRephrase.handle_callback(%{})
      assert {:error, _reason} = TemplateRephrase.handle_callback(%{"metadata" => %{}})
    end
  end
end
