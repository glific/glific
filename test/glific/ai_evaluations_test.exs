defmodule Glific.AIEvaluationsTest do
  @moduledoc false
  use Glific.DataCase, async: false

  import Ecto.Query
  import Mock

  alias Glific.{
    AIEvaluations,
    AIEvaluations.AIEvaluation,
    AIEvaluations.GoldenQA,
    AIEvaluations.OrganizationEvalRequest,
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Assistants.KnowledgeBase,
    Assistants.KnowledgeBaseVersion,
    Notifications,
    Notifications.Notification,
    Partners,
    Repo
  }

  @valid_attrs %{
    name: "test_experiment",
    status: :create_in_progress,
    golden_qa_id: 123,
    kaapi_evaluation_id: 123,
    assistant_config_version_id: 1
  }

  @invalid_attrs %{
    name: nil,
    status: nil,
    golden_qa_id: nil,
    assistant_config_version_id: nil,
    kaapi_evaluation_id: nil
  }

  describe "changeset/2" do
    test "changeset with valid attributes", %{organization_id: organization_id} do
      attrs = Map.put(@valid_attrs, :organization_id, organization_id)
      changeset = AIEvaluation.changeset(%AIEvaluation{}, attrs)
      assert changeset.valid?
    end

    test "changeset with invalid attributes", %{organization_id: organization_id} do
      attrs = Map.put(@invalid_attrs, :organization_id, organization_id)
      changeset = AIEvaluation.changeset(%AIEvaluation{}, attrs)
      refute changeset.valid?

      assert %{
               name: ["can't be blank"],
               golden_qa_id: ["can't be blank"],
               assistant_config_version_id: ["can't be blank"],
               status: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "changeset without organization_id" do
      changeset = AIEvaluation.changeset(%AIEvaluation{}, @valid_attrs)
      refute changeset.valid?
      assert %{organization_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset sets default status to create_in_progress", %{
      organization_id: organization_id
    } do
      attrs =
        @valid_attrs
        |> Map.put(:organization_id, organization_id)
        |> Map.delete(:status)

      changeset = AIEvaluation.changeset(%AIEvaluation{}, attrs)
      assert changeset.valid?
      assert changeset.data.status == :create_in_progress
    end

    test "changeset with optional fields", %{organization_id: organization_id} do
      attrs =
        @valid_attrs
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:failure_reason, "Something went wrong")
        |> Map.put(:kaapi_evaluation_id, 123)
        |> Map.put(:results, %{"score" => 0.95})

      changeset = AIEvaluation.changeset(%AIEvaluation{}, attrs)
      assert changeset.valid?
      assert changeset.changes.failure_reason == "Something went wrong"
      assert changeset.changes.results == %{"score" => 0.95}
    end
  end

  describe "update_ai_evaluation/2" do
    test "updates evaluation fields via changeset", %{organization_id: organization_id} do
      config_version = create_config_version(organization_id)
      evaluation = create_evaluation(organization_id, config_version.id)
      score = %{"score" => 0.92, "total" => 100}

      assert {:ok, updated} =
               AIEvaluations.update_ai_evaluation(evaluation, %{
                 status: :completed,
                 results: score,
                 kaapi_evaluation_id: 999
               })

      assert updated.status == :completed
      assert updated.results == score
      assert updated.kaapi_evaluation_id == 999
    end
  end

  describe "poll_and_update/1 - polling logic" do
    setup %{organization_id: organization_id} do
      enable_kaapi(organization_id)
      config_version = create_config_version(organization_id)
      evaluation = create_evaluation(organization_id, config_version.id, %{status: :processing})
      %{evaluation: evaluation, config_version: config_version}
    end

    test "updates evaluation to completed when Kaapi returns completed", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      summary_scores = [
        %{name: "Cosine Similarity", avg: 0.74, std: 0.1, data_type: "NUMERIC", total_pairs: 25}
      ]

      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            data: %{status: "completed", score: %{summary_scores: summary_scores, traces: []}}
          }
        }
      end)

      notification_count =
        Notifications.count_notifications(%{filter: %{organization_id: organization_id}})

      AIEvaluations.poll_and_update(organization_id)

      {:ok, updated} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert updated.status == :completed
      assert length(updated.results["summary_scores"]) == 1
      assert hd(updated.results["summary_scores"])["name"] == "Cosine Similarity"
      assert hd(updated.results["summary_scores"])["avg"] == 0.74

      assert Notifications.count_notifications(%{filter: %{organization_id: organization_id}}) ==
               notification_count + 1

      {:ok, notification} =
        Repo.fetch_by(Notification, %{organization_id: organization_id, category: "AI Evaluation"})

      assert notification.severity == Notifications.types().info
      assert notification.message =~ "completed successfully"
    end

    test "sets empty summary_scores when Kaapi completed response has no score", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: %{data: %{status: "completed"}}}
      end)

      AIEvaluations.poll_and_update(organization_id)

      {:ok, updated} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert updated.status == :completed
      assert updated.results == %{"summary_scores" => []}
    end

    test "updates evaluation to failed when Kaapi returns failed with reason", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{data: %{status: "failed", error_message: "Model inference error"}}
        }
      end)

      notification_count =
        Notifications.count_notifications(%{filter: %{organization_id: organization_id}})

      AIEvaluations.poll_and_update(organization_id)

      {:ok, updated} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert updated.status == :failed
      assert updated.failure_reason == "Model inference error"

      assert Notifications.count_notifications(%{filter: %{organization_id: organization_id}}) ==
               notification_count + 1

      {:ok, notification} =
        Repo.fetch_by(Notification, %{organization_id: organization_id, category: "AI Evaluation"})

      assert notification.severity == Notifications.types().warning
      assert notification.message =~ "Model inference error"
    end

    test "uses default failure reason when Kaapi failed response has no reason", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: %{data: %{status: "failed"}}}
      end)

      AIEvaluations.poll_and_update(organization_id)

      {:ok, updated} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert updated.status == :failed
      assert updated.failure_reason == "Evaluation failed"
    end

    test "leaves evaluation unchanged when Kaapi returns still processing", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: %{data: %{status: "processing"}}}
      end)

      AIEvaluations.poll_and_update(organization_id)

      {:ok, unchanged} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert unchanged.status == :processing
    end

    test "logs error and leaves evaluation unchanged when Kaapi returns 500", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 500, body: %{error: "Internal server error"}}
      end)

      AIEvaluations.poll_and_update(organization_id)

      {:ok, unchanged} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert unchanged.status == :processing
    end

    test "concurrent polls only complete the evaluation and notify once", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      summary_scores = [
        %{name: "Cosine Similarity", avg: 0.74, std: 0.1, data_type: "NUMERIC", total_pairs: 25}
      ]

      Tesla.Mock.mock_global(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            data: %{status: "completed", score: %{summary_scores: summary_scores, traces: []}}
          }
        }
      end)

      notification_count =
        Notifications.count_notifications(%{filter: %{organization_id: organization_id}})

      [task_one, task_two] =
        Enum.map(1..2, fn _ ->
          Task.async(fn ->
            Repo.put_organization_id(organization_id)
            AIEvaluations.poll_and_update(organization_id)
          end)
        end)

      Task.await(task_one)
      Task.await(task_two)

      {:ok, updated} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert updated.status == :completed

      assert Notifications.count_notifications(%{filter: %{organization_id: organization_id}}) ==
               notification_count + 1
    end
  end

  defp create_config_version(organization_id) do
    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{name: "Test Assistant", organization_id: organization_id})
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        prompt: "You are a helpful assistant.",
        provider: "openai",
        model: "gpt-4o",
        settings: %{"temperature" => 1.0},
        status: :ready,
        organization_id: organization_id
      })
      |> Repo.insert()

    config_version
  end

  defp create_golden_qa(organization_id) do
    {:ok, golden_qa} =
      %GoldenQA{}
      |> GoldenQA.changeset(%{
        name: "test_golden_qa_#{System.unique_integer([:positive])}",
        dataset_id: 1,
        organization_id: organization_id
      })
      |> Repo.insert()

    golden_qa
  end

  defp create_evaluation(organization_id, config_version_id, attrs \\ %{}) do
    golden_qa_id =
      Map.get_lazy(attrs, :golden_qa_id, fn -> create_golden_qa(organization_id).id end)

    base = %{
      name: "test_eval_#{System.unique_integer([:positive])}",
      status: :processing,
      golden_qa_id: golden_qa_id,
      kaapi_evaluation_id: 404,
      assistant_config_version_id: config_version_id,
      organization_id: organization_id
    }

    {:ok, evaluation} =
      %AIEvaluation{}
      |> AIEvaluation.changeset(Map.merge(base, attrs))
      |> Repo.insert()

    evaluation
  end

  describe "request_eval_access/1" do
    test "creates a new request with status requested", %{organization_id: organization_id} do
      Application.put_env(:glific, :discord_webhook_url, "https://discord.test/webhook")
      on_exit(fn -> Application.delete_env(:glific, :discord_webhook_url) end)

      Tesla.Mock.mock(fn %{method: :post} -> %Tesla.Env{status: 200, body: ""} end)

      assert {:ok, %OrganizationEvalRequest{status: "requested"}} =
               AIEvaluations.request_eval_access(organization_id)
    end

    test "sends Discord notification on new request", %{organization_id: organization_id} do
      Application.put_env(:glific, :discord_webhook_url, "https://discord.test/webhook")
      on_exit(fn -> Application.delete_env(:glific, :discord_webhook_url) end)

      test_pid = self()

      Tesla.Mock.mock(fn %{method: :post} = env ->
        send(test_pid, {:discord_called, env.body})
        %Tesla.Env{status: 200, body: ""}
      end)

      AIEvaluations.request_eval_access(organization_id)

      assert_received {:discord_called, body}
      decoded = Jason.decode!(body)
      [embed] = decoded["embeds"]
      assert embed["title"] =~ "AI Evaluations Access Request"
    end

    test "returns existing request and does not send Discord notification again", %{
      organization_id: organization_id
    } do
      Application.put_env(:glific, :discord_webhook_url, "https://discord.test/webhook")
      on_exit(fn -> Application.delete_env(:glific, :discord_webhook_url) end)

      test_pid = self()

      Tesla.Mock.mock(fn %{method: :post} = env ->
        send(test_pid, {:discord_called, env.body})
        %Tesla.Env{status: 200, body: ""}
      end)

      {:ok, first} = AIEvaluations.request_eval_access(organization_id)
      {:ok, second} = AIEvaluations.request_eval_access(organization_id)

      assert first.id == second.id
      assert_received {:discord_called, _}
      refute_received {:discord_called, _}
    end
  end

  describe "get_eval_access_request/1" do
    test "returns error tuple when no request exists", %{organization_id: organization_id} do
      assert {:error, _} = AIEvaluations.get_eval_access_request(organization_id)
    end

    test "returns the request when it exists", %{organization_id: organization_id} do
      {:ok, created} = AIEvaluations.request_eval_access(organization_id)

      assert {:ok, %OrganizationEvalRequest{} = fetched} =
               AIEvaluations.get_eval_access_request(organization_id)

      assert fetched.id == created.id
      assert fetched.status == "requested"
    end
  end

  defp enable_kaapi(organization_id) do
    Partners.create_credential(%{
      organization_id: organization_id,
      shortcode: "kaapi",
      keys: %{},
      secrets: %{"api_key" => "sk_test_key"},
      is_active: true
    })

    organization_id |> Partners.get_organization!() |> Partners.fill_cache()
  end

  describe "request_improve_prompt/2" do
    setup %{organization_id: organization_id} do
      enable_kaapi(organization_id)
      config_version = create_config_version(organization_id)

      evaluation =
        create_evaluation(organization_id, config_version.id, %{
          status: :completed,
          kaapi_evaluation_id: 767
        })

      %{evaluation: evaluation}
    end

    test "dispatches to Kaapi and returns :pending without writing to the database", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      Tesla.Mock.mock(fn %{method: :post, url: url} ->
        assert url =~ "/api/v2/evaluations/767/improve-prompt"

        %Tesla.Env{
          status: 200,
          body: %{success: true, data: %{job_id: "job-uuid-123", status: "PENDING"}}
        }
      end)

      count_before = Repo.aggregate(AssistantConfigVersion, :count, :id)

      assert {:ok, %{status: "pending"}} =
               AIEvaluations.request_improve_prompt(evaluation.id, organization_id)

      assert Repo.aggregate(AssistantConfigVersion, :count, :id) == count_before
    end

    test "returns error when evaluation does not exist", %{organization_id: organization_id} do
      assert {:error, [_, "Resource not found"]} =
               AIEvaluations.request_improve_prompt(999_999, organization_id)
    end

    test "passes an upstream Kaapi error through unchanged", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      Tesla.Mock.mock(fn %{method: :post} -> {:error, :timeout} end)

      assert {:error, :timeout} =
               AIEvaluations.request_improve_prompt(evaluation.id, organization_id)
    end
  end

  describe "handle_improve_prompt_callback/2" do
    setup %{organization_id: organization_id} do
      enable_kaapi(organization_id)
      config_version = create_config_version(organization_id)
      assistant = Repo.get!(Assistant, config_version.assistant_id)

      {:ok, assistant} =
        assistant
        |> Assistant.changeset(%{kaapi_uuid: "8a322023-2f28-4880-8bd3-bbe8611af901"})
        |> Repo.update()

      %{assistant: assistant, config_version: config_version}
    end

    test "success callback builds a new :ready config version entirely from the payload", %{
      organization_id: organization_id,
      assistant: assistant,
      config_version: config_version
    } do
      params = %{
        "success" => true,
        "data" => %{
          "job_id" => "job-uuid-callback",
          "status" => "SUCCESS",
          "recommendation_type" => "prompt",
          "config_version" => %{
            "id" => "9ac7cda1-4c36-4ded-9c25-263326a6db73",
            "config_id" => assistant.kaapi_uuid,
            "version" => 6,
            "commit_message" => "[AI Generated] improved from config version v2",
            "config_blob" => %{
              "completion" => %{
                "type" => "text",
                "provider" => "openai",
                "params" => %{
                  "model" => "gpt-5.6-luna",
                  "instructions" => "You are Seva Sakhi, the official AI assistant.",
                  "temperature" => 0.4
                }
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

      assert {:ok, new_config_version} =
               AIEvaluations.handle_improve_prompt_callback(organization_id, params)

      assert Repo.aggregate(AssistantConfigVersion, :count, :id) == count_before + 1
      refute new_config_version.id == config_version.id

      assert new_config_version.status == :ready
      assert new_config_version.prompt == "You are Seva Sakhi, the official AI assistant."
      assert new_config_version.description == "[AI Generated] improved from config version v2"
      assert new_config_version.kaapi_version_number == 6
      assert new_config_version.assistant_id == assistant.id
      assert new_config_version.provider == "openai"
      # Comes straight off the payload, not copied from the base/active config
      # version — the recommendation may have been generated against a different
      # config than whatever is currently live.
      assert new_config_version.model == "gpt-5.6-luna"
      assert new_config_version.settings == %{"temperature" => 0.4}
    end

    test "success callback publishes improve_prompt_updated with the new config version", %{
      organization_id: organization_id,
      assistant: assistant
    } do
      params = %{
        "data" => %{
          "status" => "SUCCESS",
          "config_version" => %{
            "config_id" => assistant.kaapi_uuid,
            "version" => 6,
            "config_blob" => %{
              "completion" => %{
                "provider" => "openai",
                "params" => %{"model" => "gpt-5.6-luna", "instructions" => "Be helpful."}
              }
            }
          }
        }
      }

      test_pid = self()

      with_mocks([
        {Absinthe.Subscription, [],
         [
           publish: fn _endpoint, payload, opts ->
             send(test_pid, {:published, payload, opts})
             :ok
           end
         ]}
      ]) do
        assert {:ok, new_config_version} =
                 AIEvaluations.handle_improve_prompt_callback(organization_id, params)

        assert_receive {:published, payload, [{:improve_prompt_updated, topic}]}, 1000
        assert payload.status == "success"
        assert payload.config_version.id == new_config_version.id
        assert payload.error == nil
        assert topic == "#{new_config_version.organization_id}"
      end
    end

    test "success callback for a reasoning model carries effort, not temperature", %{
      organization_id: organization_id,
      assistant: assistant
    } do
      params = %{
        "data" => %{
          "status" => "SUCCESS",
          "config_version" => %{
            "config_id" => assistant.kaapi_uuid,
            "version" => 1,
            "config_blob" => %{
              "completion" => %{
                "provider" => "openai",
                "params" => %{
                  "model" => "gpt-5.6-luna",
                  "instructions" => "You are a helpful assistant.",
                  "effort" => "high"
                }
              }
            }
          }
        }
      }

      assert {:ok, new_config_version} =
               AIEvaluations.handle_improve_prompt_callback(organization_id, params)

      assert new_config_version.model == "gpt-5.6-luna"
      assert new_config_version.prompt == "You are a helpful assistant."
      assert new_config_version.settings == %{"effort" => "high"}
      refute Map.has_key?(new_config_version.settings, "temperature")
    end

    test "failure callback has no config_id to attribute to, so it just acknowledges", %{
      organization_id: organization_id
    } do
      params = %{
        "success" => true,
        "data" => %{
          "job_id" => "job-uuid-callback",
          "status" => "FAILED",
          "config_version" => nil,
          "error_message" => "Judge scores unavailable"
        }
      }

      count_before = Repo.aggregate(AssistantConfigVersion, :count, :id)

      notification_count =
        Notifications.count_notifications(%{filter: %{organization_id: organization_id}})

      assert {:ok, :acknowledged} =
               AIEvaluations.handle_improve_prompt_callback(organization_id, params)

      assert Repo.aggregate(AssistantConfigVersion, :count, :id) == count_before

      assert Notifications.count_notifications(%{filter: %{organization_id: organization_id}}) ==
               notification_count
    end

    test "failure callback publishes improve_prompt_updated when given an organization_id", %{
      organization_id: organization_id
    } do
      params = %{
        "data" => %{
          "status" => "FAILED",
          "config_version" => nil,
          "error_message" => "Judge scores unavailable"
        }
      }

      test_pid = self()

      with_mocks([
        {Absinthe.Subscription, [],
         [
           publish: fn _endpoint, payload, opts ->
             send(test_pid, {:published, payload, opts})
             :ok
           end
         ]}
      ]) do
        assert {:ok, :acknowledged} =
                 AIEvaluations.handle_improve_prompt_callback(organization_id, params)

        assert_receive {:published, payload, [{:improve_prompt_updated, topic}]}, 1000
        assert payload.status == "failed"
        assert payload.config_version == nil
        assert payload.error == "Judge scores unavailable"
        assert topic == "#{organization_id}"
      end
    end

    test "returns error when config_id in the payload matches no assistant", %{
      organization_id: organization_id
    } do
      params = %{
        "data" => %{
          "status" => "SUCCESS",
          "config_version" => %{
            "config_id" => "nonexistent-config-id",
            "config_blob" => %{
              "completion" => %{"params" => %{"instructions" => "text"}}
            }
          }
        }
      }

      assert {:error, [_, "Resource not found"]} =
               AIEvaluations.handle_improve_prompt_callback(organization_id, params)
    end

    test "malformed payload is reported and does not crash", %{organization_id: organization_id} do
      assert {:error, _reason} =
               AIEvaluations.handle_improve_prompt_callback(organization_id, %{
                 "unexpected" => "shape"
               })
    end

    test "non-terminal status is acknowledged without creating a config version", %{
      organization_id: organization_id
    } do
      params = %{"data" => %{"status" => "PENDING", "job_id" => "job-uuid-pending"}}

      count_before = Repo.aggregate(AssistantConfigVersion, :count, :id)

      assert {:ok, :acknowledged} =
               AIEvaluations.handle_improve_prompt_callback(organization_id, params)

      assert Repo.aggregate(AssistantConfigVersion, :count, :id) == count_before
    end

    test "links the matching knowledge base version when knowledge_base_ids are present", %{
      organization_id: organization_id,
      assistant: assistant
    } do
      knowledge_base_version = create_knowledge_base_version(organization_id, "llm-service-abc")

      params = %{
        "data" => %{
          "status" => "SUCCESS",
          "config_version" => %{
            "config_id" => assistant.kaapi_uuid,
            "version" => 7,
            "commit_message" => "linked knowledge base",
            "config_blob" => %{
              "completion" => %{
                "provider" => "openai",
                "params" => %{
                  "model" => "gpt-4o",
                  "instructions" => "Answer using the knowledge base.",
                  "knowledge_base_ids" => ["llm-service-abc"]
                }
              }
            }
          }
        }
      }

      assert {:ok, new_config_version} =
               AIEvaluations.handle_improve_prompt_callback(organization_id, params)

      assert Repo.all(
               from(link in "assistant_config_version_knowledge_base_versions",
                 where: link.assistant_config_version_id == ^new_config_version.id,
                 select: link.knowledge_base_version_id
               )
             ) == [knowledge_base_version.id]
    end

    test "rolls back the config version when no knowledge base matches the llm_service_id", %{
      organization_id: organization_id,
      assistant: assistant
    } do
      params = %{
        "data" => %{
          "status" => "SUCCESS",
          "config_version" => %{
            "config_id" => assistant.kaapi_uuid,
            "version" => 8,
            "config_blob" => %{
              "completion" => %{
                "params" => %{
                  "instructions" => "text",
                  "model" => "gpt-4o",
                  "knowledge_base_ids" => ["missing-llm-service"]
                }
              }
            }
          }
        }
      }

      count_before = Repo.aggregate(AssistantConfigVersion, :count, :id)

      assert {:error, reason} =
               AIEvaluations.handle_improve_prompt_callback(organization_id, params)

      assert reason =~ "No matching knowledge base found"
      assert Repo.aggregate(AssistantConfigVersion, :count, :id) == count_before
    end

    test "returns the changeset error when the config version data is invalid", %{
      organization_id: organization_id,
      assistant: assistant
    } do
      params = %{
        "data" => %{
          "status" => "SUCCESS",
          "config_version" => %{
            "config_id" => assistant.kaapi_uuid,
            "version" => 9,
            "config_blob" => %{"completion" => %{"params" => %{}}}
          }
        }
      }

      assert {:error, %Ecto.Changeset{}} =
               AIEvaluations.handle_improve_prompt_callback(organization_id, params)
    end
  end

  describe "handle_evaluation_run_callback/2" do
    setup %{organization_id: organization_id} do
      enable_kaapi(organization_id)
      config_version = create_config_version(organization_id)

      evaluation =
        create_evaluation(organization_id, config_version.id, %{
          status: :processing,
          kaapi_evaluation_id: 767
        })

      %{evaluation: evaluation}
    end

    test "completed status re-fetches full scores from Kaapi, updates the evaluation, and publishes ai_evaluation_updated",
         %{organization_id: organization_id, evaluation: evaluation} do
      summary_scores = [
        %{name: "Cosine Similarity", avg: 0.74, std: 0.1, data_type: "NUMERIC", total_pairs: 25}
      ]

      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            data: %{status: "completed", score: %{summary_scores: summary_scores, traces: []}}
          }
        }
      end)

      test_pid = self()

      with_mocks([
        {Absinthe.Subscription, [],
         [
           publish: fn _endpoint, payload, opts ->
             send(test_pid, {:published, payload, opts})
             :ok
           end
         ]}
      ]) do
        assert :ok =
                 AIEvaluations.handle_evaluation_run_callback(organization_id, %{
                   "data" => %{"id" => 767, "status" => "completed"}
                 })

        {:ok, updated} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
        assert updated.status == :completed
        assert hd(updated.results["summary_scores"])["name"] == "Cosine Similarity"

        assert_receive {:published, payload, [{:ai_evaluation_updated, topic}]}, 1000
        assert payload.id == evaluation.id
        assert payload.status == :completed
        assert topic == "#{organization_id}"
      end
    end

    test "failed status re-fetches from Kaapi and updates the evaluation to failed", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{data: %{status: "failed", error_message: "Model inference error"}}
        }
      end)

      assert :ok =
               AIEvaluations.handle_evaluation_run_callback(organization_id, %{
                 "data" => %{"id" => 767, "status" => "failed"}
               })

      {:ok, updated} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert updated.status == :failed
      assert updated.failure_reason == "Model inference error"
    end

    test "non-terminal status is acknowledged without contacting Kaapi", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      assert :ok =
               AIEvaluations.handle_evaluation_run_callback(organization_id, %{
                 "data" => %{"id" => 767, "status" => "processing"}
               })

      {:ok, unchanged} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert unchanged.status == :processing
    end

    test "unknown kaapi_evaluation_id is acknowledged without crashing", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      assert :ok =
               AIEvaluations.handle_evaluation_run_callback(organization_id, %{
                 "data" => %{"id" => 999_999, "status" => "completed"}
               })

      {:ok, unchanged} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert unchanged.status == :processing
    end

    test "malformed payload is acknowledged without crashing", %{
      organization_id: organization_id
    } do
      assert :ok =
               AIEvaluations.handle_evaluation_run_callback(organization_id, %{
                 "unexpected" => "shape"
               })
    end

    test "is a no-op when the evaluation already left :processing (race with the cron poller)",
         %{organization_id: organization_id, evaluation: evaluation} do
      {:ok, _already_completed_by_cron} =
        AIEvaluations.update_ai_evaluation(evaluation, %{
          status: :completed,
          results: %{summary_scores: []}
        })

      notification_count =
        Notifications.count_notifications(%{filter: %{organization_id: organization_id}})

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

      test_pid = self()

      with_mocks([
        {Absinthe.Subscription, [],
         [
           publish: fn _endpoint, payload, opts ->
             send(test_pid, {:published, payload, opts})
             :ok
           end
         ]}
      ]) do
        assert :ok =
                 AIEvaluations.handle_evaluation_run_callback(organization_id, %{
                   "data" => %{"id" => 767, "status" => "completed"}
                 })

        refute_receive {:published, _payload, _opts}, 200
      end

      assert Notifications.count_notifications(%{filter: %{organization_id: organization_id}}) ==
               notification_count

      {:ok, unchanged} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert unchanged.status == :completed
      assert unchanged.results == %{"summary_scores" => []}
    end
  end

  defp create_knowledge_base_version(organization_id, llm_service_id) do
    {:ok, knowledge_base} =
      %KnowledgeBase{}
      |> KnowledgeBase.changeset(%{
        name: "test_kb_#{System.unique_integer([:positive])}",
        organization_id: organization_id
      })
      |> Repo.insert()

    {:ok, knowledge_base_version} =
      %KnowledgeBaseVersion{}
      |> KnowledgeBaseVersion.changeset(%{
        knowledge_base_id: knowledge_base.id,
        organization_id: organization_id,
        files: %{},
        status: :completed,
        llm_service_id: llm_service_id
      })
      |> Repo.insert()

    knowledge_base_version
  end
end
