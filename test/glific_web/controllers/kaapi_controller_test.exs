defmodule GlificWeb.KaapiControllerTest do
  use GlificWeb.ConnCase

  alias Glific.AIEvaluations
  alias Glific.AIEvaluations.AIEvaluation
  alias Glific.Assistants
  alias Glific.Assistants.Assistant
  alias Glific.Assistants.AssistantConfigVersion
  alias Glific.Assistants.KnowledgeBaseVersion
  alias Glific.Fixtures
  alias Glific.Notifications
  alias Glific.Partners
  alias Glific.PromptGenerator.PromptGenerationRequest
  alias Glific.Repo

  describe "create_knowledge_base_version/2" do
    setup :setup_knowledge_base

    test "returns 200 and updates knowledge base version on successful callback",
         %{conn: conn, knowledge_base_version: knowledge_base_version} do
      params = %{
        "data" => %{
          "job_id" => knowledge_base_version.kaapi_job_id,
          "status" => "SUCCESSFUL",
          "collection" => %{"knowledge_base_id" => "vs_updated_789"},
          "error_message" => nil
        }
      }

      conn = post(conn, "/kaapi/knowledge_base_version", params)

      assert response(conn, 200) ==
               "Knowledge base version creation callback handled successfully"

      {:ok, updated_knowledge_base_version} =
        Repo.fetch(KnowledgeBaseVersion, knowledge_base_version.id, skip_organization_id: true)

      assert updated_knowledge_base_version.status == :completed
      assert updated_knowledge_base_version.llm_service_id == "vs_updated_789"
    end

    test "returns 200 and sets failed status on failure callback",
         %{conn: conn, knowledge_base_version: knowledge_base_version} do
      params = %{
        "data" => %{
          "job_id" => knowledge_base_version.kaapi_job_id,
          "status" => "FAILED",
          "collection" => nil,
          "error_message" => "Processing failed"
        }
      }

      conn = post(conn, "/kaapi/knowledge_base_version", params)

      assert response(conn, 200) ==
               "Knowledge base version creation callback handled successfully"

      {:ok, updated_knowledge_base_version} =
        Repo.fetch(KnowledgeBaseVersion, knowledge_base_version.id, skip_organization_id: true)

      assert updated_knowledge_base_version.status == :failed
    end

    test "updates linked assistant config version on successful callback",
         %{
           conn: conn,
           knowledge_base_version: knowledge_base_version,
           organization_id: organization_id
         } do
      Tesla.Mock.mock_global(fn
        %Tesla.Env{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{data: %{id: "kaapi_config_123", version: %{version: 1}}}
          }

        %Tesla.Env{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: %{
              data: %{
                data: [%{model_name: "gpt-4", provider: "openai", config: %{temperature: 1}}]
              }
            }
          }
      end)

      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Test Assistant",
          organization_id: organization_id
        })
        |> Repo.insert()

      {:ok, assistant_version} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4",
          prompt: "You are a helpful assistant",
          settings: %{},
          status: :in_progress
        })
        |> Repo.insert()

      {:ok, _} =
        assistant
        |> Assistant.changeset(%{active_config_version_id: assistant_version.id})
        |> Repo.update()

      Repo.insert_all(
        "assistant_config_version_knowledge_base_versions",
        [
          %{
            assistant_config_version_id: assistant_version.id,
            knowledge_base_version_id: knowledge_base_version.id,
            organization_id: organization_id,
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          }
        ]
      )

      params = %{
        "data" => %{
          "job_id" => knowledge_base_version.kaapi_job_id,
          "status" => "SUCCESSFUL",
          "collection" => %{"knowledge_base_id" => "vs_new"},
          "error_message" => nil
        }
      }

      conn = post(conn, "/kaapi/knowledge_base_version", params)

      assert response(conn, 200) ==
               "Knowledge base version creation callback handled successfully"

      {:ok, updated_knowledge_base_version} =
        Repo.fetch(KnowledgeBaseVersion, knowledge_base_version.id, skip_organization_id: true)

      updated_knowledge_base_version =
        Repo.preload(updated_knowledge_base_version, :assistant_config_versions)

      assert updated_knowledge_base_version.status == :completed

      [updated_assistant_version] = updated_knowledge_base_version.assistant_config_versions
      assert updated_assistant_version.status == :ready
    end

    test "updates linked assistant config version on failure callback",
         %{
           conn: conn,
           knowledge_base_version: knowledge_base_version,
           organization_id: organization_id
         } do
      {:ok, assistant} =
        %Assistant{}
        |> Assistant.changeset(%{
          name: "Test Assistant",
          organization_id: organization_id
        })
        |> Repo.insert()

      {:ok, assistant_version} =
        %AssistantConfigVersion{}
        |> AssistantConfigVersion.changeset(%{
          assistant_id: assistant.id,
          organization_id: organization_id,
          provider: "openai",
          model: "gpt-4",
          prompt: "You are a helpful assistant",
          settings: %{},
          status: :in_progress
        })
        |> Repo.insert()

      {:ok, _} =
        assistant
        |> Assistant.changeset(%{active_config_version_id: assistant_version.id})
        |> Repo.update()

      Repo.insert_all(
        "assistant_config_version_knowledge_base_versions",
        [
          %{
            assistant_config_version_id: assistant_version.id,
            knowledge_base_version_id: knowledge_base_version.id,
            organization_id: organization_id,
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          }
        ]
      )

      params = %{
        "data" => %{
          "job_id" => knowledge_base_version.kaapi_job_id,
          "status" => "FAILED",
          "collection" => nil,
          "error_message" => "Processing failed"
        }
      }

      conn = post(conn, "/kaapi/knowledge_base_version", params)

      assert response(conn, 200) ==
               "Knowledge base version creation callback handled successfully"

      {:ok, updated_knowledge_base_version} =
        Repo.fetch(KnowledgeBaseVersion, knowledge_base_version.id, skip_organization_id: true)

      updated_knowledge_base_version =
        Repo.preload(updated_knowledge_base_version, :assistant_config_versions)

      assert updated_knowledge_base_version.status == :failed

      [updated_assistant_version] = updated_knowledge_base_version.assistant_config_versions
      assert updated_assistant_version.status == :failed
      assert updated_assistant_version.failure_reason == "Processing failed"
    end

    test "returns 200 when job_id is not found",
         %{conn: conn} do
      params = %{
        "data" => %{
          "job_id" => "nonexistent_job",
          "status" => "SUCCESSFUL",
          "collection" => %{"knowledge_base_id" => "vs_123"},
          "error_message" => nil
        }
      }

      conn = post(conn, "/kaapi/knowledge_base_version", params)

      assert response(conn, 200) ==
               "Knowledge base version creation callback handled successfully"
    end

    test "does not update already failed knowledge base version",
         %{conn: conn, knowledge_base_version: knowledge_base_version} do
      {:ok, failed_version} =
        Assistants.update_knowledge_base_version(knowledge_base_version, %{status: :failed})

      params = %{
        "data" => %{
          "job_id" => knowledge_base_version.kaapi_job_id,
          "status" => "SUCCESSFUL",
          "collection" => %{"knowledge_base_id" => "vs_new"},
          "error_message" => nil
        }
      }

      conn = post(conn, "/kaapi/knowledge_base_version", params)

      assert response(conn, 200) ==
               "Knowledge base version creation callback handled successfully"

      {:ok, updated} =
        Repo.fetch(KnowledgeBaseVersion, knowledge_base_version.id, skip_organization_id: true)

      assert updated.status == :failed
      assert updated.updated_at == failed_version.updated_at
    end
  end

  # ---------------------------------------------------------------------------
  # prompt_generation_callback/2
  # ---------------------------------------------------------------------------

  describe "prompt_generation_callback/2" do
    setup :setup_prompt_generation

    test "returns 200 and flips row to :ready on a successful callback",
         %{conn: conn, prompt_generation_request: request} do
      params = %{
        "success" => true,
        "data" => %{
          "response" => %{
            "output" => %{
              "type" => "text",
              "content" => %{"format" => "text", "value" => "Generated prompt text from LLM."}
            }
          }
        },
        "error" => nil,
        "errors" => nil,
        "metadata" => %{"request_id" => request.request_id}
      }

      conn = post(conn, "/kaapi/prompt_generation", params)

      assert response(conn, 200) == ""

      {:ok, updated} =
        Repo.fetch(PromptGenerationRequest, request.id, skip_organization_id: true)

      assert updated.status == :ready
      assert updated.generated_prompt == "Generated prompt text from LLM."
    end

    test "returns 200 and flips row to :failed on a failed callback",
         %{conn: conn, prompt_generation_request: request} do
      params = %{
        "success" => false,
        "data" => nil,
        "error" => "LLM processing failed",
        "errors" => nil,
        "metadata" => %{"request_id" => request.request_id}
      }

      conn = post(conn, "/kaapi/prompt_generation", params)

      assert response(conn, 200) == ""

      {:ok, updated} =
        Repo.fetch(PromptGenerationRequest, request.id, skip_organization_id: true)

      assert updated.status == :failed
      assert updated.error_message == "LLM processing failed"
    end

    test "returns 200 when the request_id is not found",
         %{conn: conn} do
      params = %{
        "success" => true,
        "data" => %{"response" => %{"output" => %{"content" => %{"value" => "some text"}}}},
        "metadata" => %{"request_id" => "nonexistent_req_pg"}
      }

      conn = post(conn, "/kaapi/prompt_generation", params)
      assert response(conn, 200) == ""
    end
  end

  describe "improve_prompt_callback/2" do
    setup :setup_improve_prompt

    test "returns 200 and creates a new :ready config version from the payload on success",
         %{conn: conn, assistant: assistant, config_version: config_version} do
      params = %{
        "success" => true,
        "data" => %{
          "job_id" => "job_ctrl_001",
          "status" => "SUCCESS",
          "config_version" => %{
            "config_id" => assistant.kaapi_uuid,
            "version" => 6,
            "commit_message" => "[AI Generated] improved prompt",
            "config_blob" => %{
              "completion" => %{
                "provider" => "openai",
                "params" => %{"model" => "gpt-4o", "instructions" => "Improved system prompt"}
              }
            }
          },
          "error_message" => nil
        },
        "error" => nil,
        "errors" => nil,
        "metadata" => nil
      }

      count_before = Repo.aggregate(AssistantConfigVersion, :count, :id)

      conn = post(conn, "/kaapi/improve_prompt", params)

      assert response(conn, 200) == ""

      assert Repo.aggregate(AssistantConfigVersion, :count, :id) == count_before + 1

      new_config_version =
        Repo.get_by!(AssistantConfigVersion, kaapi_version_number: 6, assistant_id: assistant.id)

      assert new_config_version.status == :ready
      assert new_config_version.prompt == "Improved system prompt"
      assert new_config_version.description == "[AI Generated] improved prompt"
      refute new_config_version.id == config_version.id
    end

    test "returns 200 and creates no version on a failed callback", %{conn: conn} do
      params = %{
        "success" => true,
        "data" => %{
          "job_id" => "job_ctrl_001",
          "status" => "FAILED",
          "config_version" => nil,
          "error_message" => "Judge scores unavailable"
        }
      }

      count_before = Repo.aggregate(AssistantConfigVersion, :count, :id)

      conn = post(conn, "/kaapi/improve_prompt", params)

      assert response(conn, 200) == ""
      assert Repo.aggregate(AssistantConfigVersion, :count, :id) == count_before
    end

    test "returns 200 when config_id matches no assistant", %{conn: conn} do
      params = %{
        "data" => %{
          "status" => "SUCCESS",
          "config_version" => %{
            "config_id" => "nonexistent_config_id",
            "config_blob" => %{"completion" => %{"params" => %{"instructions" => "text"}}}
          }
        }
      }

      conn = post(conn, "/kaapi/improve_prompt", params)
      assert response(conn, 200) == ""
    end
  end

  describe "evaluation_run_callback/2" do
    setup :setup_evaluation_run

    test "returns 200 and updates the evaluation to completed on a successful run",
         %{conn: conn, evaluation: evaluation} do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            data: %{
              status: "completed",
              score: %{
                summary_scores: [%{name: "Cosine Similarity", avg: 0.9}],
                traces: []
              }
            }
          }
        }
      end)

      conn =
        post(conn, "/kaapi/evaluation_run", %{
          "data" => %{"id" => evaluation.kaapi_evaluation_id, "status" => "completed"}
        })

      assert response(conn, 200) == ""

      {:ok, updated_evaluation} =
        Repo.fetch(AIEvaluation, evaluation.id, skip_organization_id: true)

      assert updated_evaluation.status == :completed

      [notification] =
        Notifications.list_notifications(%{
          filter: %{organization_id: evaluation.organization_id, category: "AI Evaluation"}
        })

      assert notification.message =~ "completed successfully"
      assert notification.entity["evaluation_id"] == evaluation.id
    end

    test "returns 200 and updates the evaluation to failed on a failed run",
         %{conn: conn, evaluation: evaluation} do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{data: %{status: "failed", error_message: "Model inference error"}}
        }
      end)

      conn =
        post(conn, "/kaapi/evaluation_run", %{
          "data" => %{"id" => evaluation.kaapi_evaluation_id, "status" => "failed"}
        })

      assert response(conn, 200) == ""

      {:ok, updated_evaluation} =
        Repo.fetch(AIEvaluation, evaluation.id, skip_organization_id: true)

      assert updated_evaluation.status == :failed
      assert updated_evaluation.failure_reason == "Model inference error"

      [notification] =
        Notifications.list_notifications(%{
          filter: %{organization_id: evaluation.organization_id, category: "AI Evaluation"}
        })

      assert notification.message =~ "Model inference error"
      assert notification.entity["evaluation_id"] == evaluation.id
    end

    test "returns 200 when the kaapi_evaluation_id is not found", %{conn: conn} do
      conn =
        post(conn, "/kaapi/evaluation_run", %{
          "data" => %{"id" => 999_999, "status" => "completed"}
        })

      assert response(conn, 200) == ""
    end
  end

  defp setup_evaluation_run(%{organization_id: organization_id}) do
    Fixtures.kaapi_credential_fixture(%{organization_id: organization_id})
    assistant = Fixtures.assistant_fixture(%{organization_id: organization_id})

    config_version =
      Fixtures.assistant_config_version_fixture(%{
        assistant_id: assistant.id,
        organization_id: organization_id
      })

    {:ok, golden_qa} =
      AIEvaluations.create_golden_qa(%{
        name: "eval_run_dataset",
        dataset_id: 1,
        organization_id: organization_id
      })

    {:ok, evaluation} =
      AIEvaluations.create_ai_evaluation(%{
        name: "test_evaluation_run_ctrl",
        status: :processing,
        kaapi_evaluation_id: 890,
        golden_qa_id: golden_qa.id,
        assistant_config_version_id: config_version.id,
        organization_id: organization_id
      })

    %{evaluation: evaluation, organization_id: organization_id}
  end

  defp setup_improve_prompt(%{organization_id: organization_id}) do
    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{
        name: "Test Assistant",
        kaapi_uuid: "8a322023-2f28-4880-8bd3-bbe8611af901",
        organization_id: organization_id
      })
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        prompt: "You are a helpful assistant.",
        provider: "openai",
        model: "gpt-4o",
        settings: %{},
        status: :ready,
        organization_id: organization_id
      })
      |> Repo.insert()

    {:ok, golden_qa} =
      AIEvaluations.create_golden_qa(%{
        name: "eval_improve_prompt_dataset",
        dataset_id: 1,
        organization_id: organization_id
      })

    {:ok, evaluation} =
      %AIEvaluation{}
      |> AIEvaluation.changeset(%{
        name: "test_evaluation_ctrl",
        status: :completed,
        kaapi_evaluation_id: 767,
        golden_qa_id: golden_qa.id,
        assistant_config_version_id: config_version.id,
        organization_id: organization_id
      })
      |> Repo.insert()

    %{
      evaluation: evaluation,
      assistant: assistant,
      config_version: config_version,
      organization_id: organization_id
    }
  end

  defp setup_prompt_generation(%{organization_id: organization_id}) do
    {:ok, credential} =
      Partners.create_credential(%{
        organization_id: organization_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"}
      })

    {:ok, _credential} =
      Partners.update_credential(credential, %{
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"},
        is_active: true,
        organization_id: organization_id,
        shortcode: "kaapi"
      })

    {:ok, request} =
      %PromptGenerationRequest{}
      |> PromptGenerationRequest.changeset(%{
        inputs: %{"name" => "Test NGO"},
        status: :in_progress,
        request_id: "req_pg_ctrl_001",
        organization_id: organization_id
      })
      |> Repo.insert()

    %{prompt_generation_request: request, organization_id: organization_id}
  end

  defp setup_knowledge_base(%{organization_id: organization_id}) do
    {:ok, credential} =
      Glific.Partners.create_credential(%{
        organization_id: organization_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"}
      })

    {:ok, _credential} =
      Glific.Partners.update_credential(credential, %{
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"},
        is_active: true,
        organization_id: organization_id,
        shortcode: "kaapi"
      })

    {:ok, knowledge_base} =
      Assistants.create_knowledge_base(%{
        name: "Test Knowledge Base",
        organization_id: organization_id
      })

    {:ok, knowledge_base_version} =
      Assistants.create_knowledge_base_version(%{
        knowledge_base_id: knowledge_base.id,
        organization_id: organization_id,
        files: %{"file_123" => %{"name" => "test_file.txt"}},
        status: :in_progress,
        llm_service_id: "temp_vs_12345",
        kaapi_job_id: "job_abc123",
        size: 100
      })

    %{
      knowledge_base_version: knowledge_base_version,
      organization_id: organization_id
    }
  end
end
