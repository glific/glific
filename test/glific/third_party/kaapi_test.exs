defmodule Glific.ThirdParty.KaapiTest do
  use GlificWeb.ConnCase
  import Tesla.Mock
  alias Glific.Fixtures
  alias Glific.Partners
  alias Glific.ThirdParty.Kaapi

  @llm_call_payload %{
    query: %{input: "Hello", conversation: %{auto_create: true}},
    config: %{id: "kaapi_uuid", version: 1},
    callback_url: "https://api.glific.glific.com/kaapi/llm_call",
    request_metadata: %{request_id: "req-1", user_id: 9}
  }

  describe "upload_evaluation_dataset/2" do
    setup [:enable_kaapi_credential, :create_dataset_upload_params]

    test "extracts name and dataset_id from a well-shaped v1 response", %{
      organization_id: organization_id,
      dataset_params: dataset_params
    } do
      mock(fn %Tesla.Env{method: :post, url: url} ->
        assert url =~ "/api/v1/evaluations/datasets"

        %Tesla.Env{
          status: 200,
          body: %{data: %{dataset_name: "valid_dataset", dataset_id: "88002"}}
        }
      end)

      assert {:ok, %{name: "valid_dataset", dataset_id: "88002"}} =
               Kaapi.upload_evaluation_dataset(dataset_params, organization_id)
    end

    test "returns a generic error and does not crash on an unexpected response shape", %{
      organization_id: organization_id,
      dataset_params: dataset_params
    } do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 200, body: %{data: %{unexpected: "shape"}}}
      end)

      assert {:error, "An unknown error occurred, please contact Glific support."} =
               Kaapi.upload_evaluation_dataset(dataset_params, organization_id)
    end

    test "passes an upstream error through unchanged", %{
      organization_id: organization_id,
      dataset_params: dataset_params
    } do
      mock(fn %Tesla.Env{method: :post} -> {:error, :timeout} end)

      assert {:error, :timeout} = Kaapi.upload_evaluation_dataset(dataset_params, organization_id)
    end
  end

  describe "upload_evaluation_dataset_v2/2" do
    setup [:enable_kaapi_credential, :create_dataset_upload_params]

    test "extracts dataset_id and total_items from a well-shaped v2 response", %{
      organization_id: organization_id,
      dataset_params: dataset_params
    } do
      mock(fn %Tesla.Env{method: :post, url: url} ->
        assert url =~ "/api/v2/evaluations/datasets"

        %Tesla.Env{status: 200, body: %{data: %{dataset_id: "99002", total_items: 55}}}
      end)

      assert {:ok, %{dataset_id: "99002", total_items: 55}} =
               Kaapi.upload_evaluation_dataset_v2(dataset_params, organization_id)
    end

    test "returns a generic error and does not crash when total_items is missing", %{
      organization_id: organization_id,
      dataset_params: dataset_params
    } do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 200, body: %{data: %{dataset_id: "99003"}}}
      end)

      assert {:error, "An unknown error occurred, please contact Glific support."} =
               Kaapi.upload_evaluation_dataset_v2(dataset_params, organization_id)
    end
  end

  describe "create_evaluation_v2/2" do
    setup [:enable_kaapi_credential]

    @evaluation_params %{
      experiment_name: "antaratrial",
      config_id: "d186d8eb-1211-4a7b-aa28-e8a22f8163c9",
      config_version: 7,
      dataset_id: 651
    }

    test "forwards a well-shaped v2 response unchanged", %{organization_id: organization_id} do
      mock(fn %Tesla.Env{method: :post, url: url} ->
        assert url =~ "/api/v2/evaluations"

        %Tesla.Env{
          status: 200,
          body: %{data: %{id: 777, run_name: "antaratrial", status: "processing"}}
        }
      end)

      assert {:ok, %{data: %{id: 777, status: "processing"}}} =
               Kaapi.create_evaluation_v2(@evaluation_params, organization_id)
    end

    test "passes an upstream error through unchanged", %{organization_id: organization_id} do
      mock(fn %Tesla.Env{method: :post} -> {:error, :timeout} end)

      assert {:error, :timeout} = Kaapi.create_evaluation_v2(@evaluation_params, organization_id)
    end
  end

  describe "llm_call/2" do
    setup [:enable_kaapi_credential]

    test "returns job_id and conversation_id on a successful dispatch", %{
      organization_id: organization_id
    } do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{data: %{job_id: "job_001", conversation: %{id: "conv_001"}}}
        }
      end)

      assert {:ok, %{job_id: "job_001", conversation_id: "conv_001"}} =
               Kaapi.llm_call(@llm_call_payload, organization_id)
    end

    test "returns nil conversation_id when Kaapi doesn't echo one back", %{
      organization_id: organization_id
    } do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 200, body: %{data: %{job_id: "job_002"}}}
      end)

      assert {:ok, %{job_id: "job_002", conversation_id: nil}} =
               Kaapi.llm_call(@llm_call_payload, organization_id)
    end

    test "returns an error for an unexpected 2xx body shape", %{organization_id: organization_id} do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 200, body: %{unexpected: "shape"}}
      end)

      assert {:error, _reason} = Kaapi.llm_call(@llm_call_payload, organization_id)
    end

    test "returns an error when Kaapi is not configured for the org" do
      organization = Fixtures.organization_fixture()

      assert {:error, "\"Kaapi is not active\""} =
               Kaapi.llm_call(@llm_call_payload, organization.id)
    end

    test "returns the Kaapi error message on a config-not-found 422", %{
      organization_id: organization_id
    } do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 422,
          body: %{
            success: false,
            data: nil,
            error: "Failed to retrieve stored configuration: config with id 'bad-id' not found",
            errors: nil,
            metadata: %{}
          }
        }
      end)

      assert {:error,
              "Failed to retrieve stored configuration: config with id 'bad-id' not found"} =
               Kaapi.llm_call(%{}, organization_id)
    end

    test "returns the field-level message on a validation-failed 422", %{
      organization_id: organization_id
    } do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 422,
          body: %{
            success: false,
            data: nil,
            error: "Validation failed",
            errors: [
              %{field: "config.id", message: "Input should be a valid UUID"}
            ],
            metadata: nil
          }
        }
      end)

      assert {:error, "config.id: Input should be a valid UUID"} =
               Kaapi.llm_call(%{}, organization_id)
    end
  end

  describe "get_document/2" do
    setup [:enable_kaapi_credential]

    test "returns document data with signed_url", %{organization_id: organization_id} do
      mock(fn %Tesla.Env{method: :get, url: url} ->
        assert url =~ "/api/v1/documents/doc_123"

        %Tesla.Env{
          status: 200,
          body: %{
            success: true,
            data: %{
              id: "doc_123",
              fname: "biu-1.pdf",
              signed_url: "https://kaapi-test.s3.amazonaws.com/test/biu-1.pdf"
            }
          }
        }
      end)

      assert {:ok, %{id: "doc_123", signed_url: signed_url}} =
               Kaapi.get_document("doc_123", organization_id)

      assert signed_url == "https://kaapi-test.s3.amazonaws.com/test/biu-1.pdf"
    end

    test "returns an error when signed_url is missing", %{
      organization_id: organization_id
    } do
      mock(fn %Tesla.Env{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{success: true, data: %{id: "doc_123", fname: "biu-1.pdf"}}
        }
      end)

      assert {:error, "File download URL not available"} =
               Kaapi.get_document("doc_123", organization_id)
    end

    test "passes an upstream error through unchanged", %{organization_id: organization_id} do
      mock(fn %Tesla.Env{method: :get} -> {:error, :timeout} end)

      assert {:error, :timeout} = Kaapi.get_document("doc_123", organization_id)
    end
  end

  describe "improve_evaluation_prompt/3" do
    setup [:enable_kaapi_credential]

    test "extracts job_id from a well-shaped v2 response", %{organization_id: organization_id} do
      mock(fn %Tesla.Env{method: :post, url: url} ->
        assert url =~ "/api/v2/evaluations/767/improve-prompt"

        %Tesla.Env{
          status: 200,
          body: %{
            success: true,
            data: %{job_id: "a8f2be70-4ac6-42af-ada7-c28ac46fd834", status: "PENDING"}
          }
        }
      end)

      assert {:ok, %{job_id: "a8f2be70-4ac6-42af-ada7-c28ac46fd834"}} =
               Kaapi.improve_evaluation_prompt(
                 767,
                 "https://example.com/kaapi/improve_prompt",
                 organization_id
               )
    end

    test "passes an upstream error through unchanged", %{organization_id: organization_id} do
      mock(fn %Tesla.Env{method: :post} -> {:error, :timeout} end)

      assert {:error, :timeout} =
               Kaapi.improve_evaluation_prompt(
                 767,
                 "https://example.com/kaapi/improve_prompt",
                 organization_id
               )
    end
  end

  describe "list_models/1" do
    setup [:enable_kaapi_credential]

    setup do
      Cachex.del(:glific_cache, {:global, {:kaapi_models, "openai"}})
      :ok
    end

    test "fetches and returns the model list" do
      mock(fn %Tesla.Env{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{data: %{data: [%{provider: "openai", model_name: "gpt-4.1"}]}}
        }
      end)

      assert {:ok, models} = Kaapi.list_models(1)
      assert Enum.map(models, & &1.model_name) == ["gpt-4.1"]
    end

    test "serves the cached list on a subsequent call without another Kaapi request" do
      mock(fn %Tesla.Env{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{data: %{data: [%{provider: "openai", model_name: "gpt-4o"}]}}
        }
      end)

      assert {:ok, _models} = Kaapi.list_models(1)

      mock(fn %Tesla.Env{} -> raise "Kaapi should not be called again while cache is warm" end)

      assert {:ok, models} = Kaapi.list_models(1)
      assert Enum.map(models, & &1.model_name) == ["gpt-4o"]
    end

    test "returns error and does not cache when Kaapi returns an unexpected 200 body" do
      mock(fn %Tesla.Env{method: :get} ->
        %Tesla.Env{status: 200, body: %{unexpected: "shape"}}
      end)

      assert {:error, reason} = Kaapi.list_models(1)
      assert reason =~ "Unexpected Kaapi list_models response"
      assert Cachex.get(:glific_cache, {:global, {:kaapi_models, "openai"}}) == {:ok, nil}
    end

    test "returns an empty list without caching it when Kaapi has no active models" do
      mock(fn %Tesla.Env{method: :get} ->
        %Tesla.Env{status: 200, body: %{data: %{data: []}}}
      end)

      assert {:ok, []} = Kaapi.list_models(1)
      assert Cachex.get(:glific_cache, {:global, {:kaapi_models, "openai"}}) == {:ok, nil}
    end
  end

  describe "list_models_with_metadata/1" do
    setup [:enable_kaapi_credential]

    setup do
      Cachex.del(:glific_cache, {:global, {:kaapi_models, "openai"}})
      :ok
    end

    defp mock_models(model_names) do
      mock(fn %Tesla.Env{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            data: %{data: Enum.map(model_names, &%{provider: "openai", model_name: &1})}
          }
        }
      end)
    end

    test "annotates recommended, all and to-be-deprecated models" do
      mock_models(["gpt-4o", "gpt-4.1", "gpt-5-nano", "gpt-5.6-luna"])

      assert {:ok, models} = Kaapi.list_models_with_metadata(1)

      assert Enum.map(models, &{&1.model_name, &1.category, &1.badge}) == [
               {"gpt-5.6-luna", "recommended", "Best value"},
               {"gpt-5-nano", "recommended", "Fastest"},
               {"gpt-4.1", "all", nil},
               {"gpt-4o", "to_be_deprecated", "Deprecating"}
             ]
    end

    test "orders recommended by the curated order, then all alphabetically, then to-be-deprecated" do
      mock_models([
        "gpt-4o-mini",
        "o3",
        "gpt-4o",
        "gpt-5.4",
        "gpt-5.2-pro",
        "gpt-5-mini",
        "gpt-5.6-luna"
      ])

      assert {:ok, models} = Kaapi.list_models_with_metadata(1)

      assert Enum.map(models, &{&1.model_name, &1.category, &1.badge}) == [
               {"gpt-5.6-luna", "recommended", "Best value"},
               {"gpt-5-mini", "recommended", "Budget"},
               {"gpt-5.4", "recommended", "All-rounder"},
               {"gpt-5.2-pro", "all", nil},
               {"o3", "all", nil},
               {"gpt-4o", "to_be_deprecated", "Deprecating"},
               {"gpt-4o-mini", "to_be_deprecated", "Deprecating"}
             ]
    end

    test "does not inject curated models that Kaapi did not return" do
      mock_models(["gpt-4.1"])

      assert {:ok, models} = Kaapi.list_models_with_metadata(1)
      assert Enum.map(models, & &1.model_name) == ["gpt-4.1"]
    end

    test "keeps the default model unchanged until the recommended list is adopted" do
      assert Kaapi.default_model() == "gpt-4o"
    end

    test "propagates the error when the model list cannot be fetched" do
      mock(fn %Tesla.Env{method: :get} ->
        %Tesla.Env{status: 200, body: %{unexpected: "shape"}}
      end)

      assert {:error, reason} = Kaapi.list_models_with_metadata(1)
      assert reason =~ "Unexpected Kaapi list_models response"
    end
  end

  describe "list_models/1 without kaapi configured" do
    test "returns error when Kaapi is not active for the organization" do
      Cachex.del(:glific_cache, {:global, {:kaapi_models, "openai"}})

      assert {:error, "Kaapi is not active"} = Kaapi.list_models(1)
    end
  end

  describe "create_assistant_config/2 settings passthrough" do
    setup [:enable_kaapi_credential]

    test "forwards temperature/top_p settings as-is for a classic (non-reasoning) model" do
      mock(fn %Tesla.Env{method: :post, body: body} ->
        decoded_body = Jason.decode!(body)

        assert decoded_body["name"] == "GPT-4.1 Assistant"
        assert decoded_body["commit_message"] == "Assistant configuration"

        assert decoded_body["config_blob"]["completion"]["params"] == %{
                 "model" => "gpt-4.1",
                 "instructions" => "You are a helpful assistant",
                 "knowledge_base_ids" => [],
                 "temperature" => 0.01,
                 "top_p" => 1,
                 "max_output_tokens" => 2048
               }

        %Tesla.Env{
          status: 200,
          body: %{
            success: true,
            data: %{id: "asst_1", version: %{version: 1}},
            metadata: %{}
          }
        }
      end)

      params = %{
        name: "GPT-4.1 Assistant",
        model: "gpt-4.1",
        prompt: "You are a helpful assistant",
        description: "Assistant configuration",
        knowledge_base_ids: [],
        settings: %{"temperature" => 0.01, "top_p" => 1, "max_output_tokens" => 2048}
      }

      assert {:ok, %{success: true, data: %{id: "asst_1", version: %{version: 1}}}} =
               Kaapi.create_assistant_config(params, 1)
    end

    test "forwards effort settings for a reasoning model, without a stray temperature" do
      mock(fn %Tesla.Env{method: :post, body: body} ->
        decoded_body = Jason.decode!(body)

        assert decoded_body["name"] == "GPT-5.1 Assistant"
        assert decoded_body["commit_message"] == "Assistant configuration"

        assert decoded_body["config_blob"]["completion"]["params"] == %{
                 "model" => "gpt-5.1",
                 "instructions" => "You are a helpful assistant",
                 "knowledge_base_ids" => [],
                 "effort" => "none"
               }

        %Tesla.Env{
          status: 200,
          body: %{
            success: true,
            data: %{id: "asst_2", version: %{version: 1}},
            metadata: %{}
          }
        }
      end)

      params = %{
        name: "GPT-5.1 Assistant",
        model: "gpt-5.1",
        prompt: "You are a helpful assistant",
        description: "Assistant configuration",
        knowledge_base_ids: [],
        settings: %{"effort" => "none"}
      }

      assert {:ok, %{success: true, data: %{id: "asst_2", version: %{version: 1}}}} =
               Kaapi.create_assistant_config(params, 1)
    end

    test "defaults temperature to 1 for a classic model when no tunable setting is given" do
      Cachex.del(:glific_cache, {:global, {:kaapi_models, "openai"}})

      mock(fn
        %Tesla.Env{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: %{
              data: %{
                data: [
                  %{
                    provider: "openai",
                    model_name: "gpt-4o",
                    config: %{temperature: %{default: 1}}
                  }
                ]
              }
            }
          }

        %Tesla.Env{method: :post, body: body} ->
          decoded_body = Jason.decode!(body)

          assert decoded_body["config_blob"]["completion"]["params"] == %{
                   "model" => "gpt-4o",
                   "instructions" => "You are a helpful assistant",
                   "knowledge_base_ids" => [],
                   "temperature" => 1
                 }

          %Tesla.Env{
            status: 200,
            body: %{success: true, data: %{id: "asst_3", version: %{version: 1}}, metadata: %{}}
          }
      end)

      params = %{
        name: "GPT-4o Assistant",
        model: "gpt-4o",
        prompt: "You are a helpful assistant",
        description: "Assistant configuration",
        knowledge_base_ids: [],
        settings: %{}
      }

      assert {:ok, %{success: true, data: %{id: "asst_3", version: %{version: 1}}}} =
               Kaapi.create_assistant_config(params, 1)
    end

    test "falls back to the default model when the caller supplies none" do
      Cachex.del(:glific_cache, {:global, {:kaapi_models, "openai"}})

      mock(fn
        %Tesla.Env{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: %{
              data: %{
                data: [
                  %{
                    provider: "openai",
                    model_name: Kaapi.default_model(),
                    config: %{temperature: %{default: 1}}
                  }
                ]
              }
            }
          }

        %Tesla.Env{method: :post, body: body} ->
          decoded_body = Jason.decode!(body)

          assert decoded_body["config_blob"]["completion"]["params"]["model"] ==
                   Kaapi.default_model()

          %Tesla.Env{
            status: 200,
            body: %{success: true, data: %{id: "asst_6", version: %{version: 1}}, metadata: %{}}
          }
      end)

      params = %{
        name: "Default Model Assistant",
        model: nil,
        prompt: "You are a helpful assistant",
        description: "Assistant configuration",
        knowledge_base_ids: [],
        settings: %{}
      }

      assert {:ok, %{success: true, data: %{id: "asst_6", version: %{version: 1}}}} =
               Kaapi.create_assistant_config(params, 1)
    end

    test "defaults effort to low for a reasoning model when no tunable setting is given" do
      Cachex.del(:glific_cache, {:global, {:kaapi_models, "openai"}})

      mock(fn
        %Tesla.Env{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: %{
              data: %{
                data: [
                  %{
                    provider: "openai",
                    model_name: "gpt-5.1",
                    config: %{effort: %{default: "medium"}}
                  }
                ]
              }
            }
          }

        %Tesla.Env{method: :post, body: body} ->
          decoded_body = Jason.decode!(body)

          assert decoded_body["config_blob"]["completion"]["params"] == %{
                   "model" => "gpt-5.1",
                   "instructions" => "You are a helpful assistant",
                   "knowledge_base_ids" => [],
                   "effort" => "low"
                 }

          %Tesla.Env{
            status: 200,
            body: %{success: true, data: %{id: "asst_4", version: %{version: 1}}, metadata: %{}}
          }
      end)

      params = %{
        name: "GPT-5.1 Assistant",
        model: "gpt-5.1",
        prompt: "You are a helpful assistant",
        description: "Assistant configuration",
        knowledge_base_ids: [],
        settings: %{}
      }

      assert {:ok, %{success: true, data: %{id: "asst_4", version: %{version: 1}}}} =
               Kaapi.create_assistant_config(params, 1)
    end

    test "adds neither temperature nor effort for a model whose config supports neither" do
      Cachex.del(:glific_cache, {:global, {:kaapi_models, "openai"}})

      mock(fn
        %Tesla.Env{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: %{
              data: %{
                data: [
                  %{
                    provider: "openai",
                    model_name: "gpt-5.2-pro",
                    config: %{summary: %{default: "auto"}}
                  }
                ]
              }
            }
          }

        %Tesla.Env{method: :post, body: body} ->
          decoded_body = Jason.decode!(body)

          assert decoded_body["config_blob"]["completion"]["params"] == %{
                   "model" => "gpt-5.2-pro",
                   "instructions" => "You are a helpful assistant",
                   "knowledge_base_ids" => []
                 }

          %Tesla.Env{
            status: 200,
            body: %{success: true, data: %{id: "asst_5", version: %{version: 1}}, metadata: %{}}
          }
      end)

      params = %{
        name: "GPT-5.2 Pro Assistant",
        model: "gpt-5.2-pro",
        prompt: "You are a helpful assistant",
        description: "Assistant configuration",
        knowledge_base_ids: [],
        settings: %{}
      }

      assert {:ok, %{success: true, data: %{id: "asst_5", version: %{version: 1}}}} =
               Kaapi.create_assistant_config(params, 1)
    end
  end

  describe "normalize_kaapi_body/1" do
    test "treats a 200 body with success:false as a logical failure" do
      assert %{
               success: false,
               http_status: 200,
               error_type: "kaapi_logical_failure",
               reason: "boom"
             } = Kaapi.normalize_kaapi_body(%{success: false, message: "boom"})
    end

    test "falls back to the error key, then to a default reason" do
      assert %{reason: "bad"} =
               Kaapi.normalize_kaapi_body(%{success: false, error: "bad"})

      assert %{reason: "Kaapi logical failure"} =
               Kaapi.normalize_kaapi_body(%{success: false})
    end
  end

  defp enable_kaapi_credential(%{organization_id: organization_id}) do
    Partners.create_credential(%{
      organization_id: organization_id,
      shortcode: "kaapi",
      keys: %{},
      secrets: %{"api_key" => "sk_test_key"},
      is_active: true
    })

    :ok
  end

  defp create_dataset_upload_params(_context) do
    tmp_path =
      Path.join(
        System.tmp_dir!(),
        "kaapi_dataset_test_#{System.unique_integer([:positive])}.csv"
      )

    File.write!(tmp_path, "question,answer\nWhat is Glific?,A communication platform\n")
    on_exit(fn -> File.rm(tmp_path) end)

    upload = %Plug.Upload{path: tmp_path, content_type: "text/csv", filename: "dataset.csv"}

    %{
      dataset_params: %{
        file: upload,
        dataset_name: "valid_dataset",
        duplication_factor: 2
      }
    }
  end
end
