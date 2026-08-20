defmodule Glific.ThirdParty.Kaapi.ApiClientTest do
  use GlificWeb.ConnCase
  import Tesla.Mock
  alias Glific.ThirdParty.Kaapi.ApiClient

  @params %{
    organization_id: 1,
    user_name: "glific",
    organization_name: "GLific_org",
    project_name: "Glific"
  }

  @org_kaapi_api_key "sk_test_key"

  test "onboard_to_kaapi/1 returns {:ok, %{api_key: key}} on 200 with api_key" do
    mock(fn
      %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{api_key: "ApiKey XoxxxxabcDefGhfKSDrs"}
        }
    end)

    assert {:ok, %{api_key: key}} = ApiClient.onboard_to_kaapi(@params)
    assert key == "ApiKey XoxxxxabcDefGhfKSDrs"
  end

  test "returns {:error, msg} when API returns body with error field" do
    mock(fn
      %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 422,
          body: %{error: "API key already exists for this user and project."}
        }
    end)

    assert {:error,
            %{status: 422, body: %{error: "API key already exists for this user and project."}}} =
             ApiClient.onboard_to_kaapi(@params)
  end

  test "returns {:error, msg} when API returns error status code (400+)" do
    mock(fn
      %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 400,
          body: %{error: "Bad request"}
        }
    end)

    assert {:error, %{status: 400, body: %{error: "Bad request"}}} =
             ApiClient.onboard_to_kaapi(@params)
  end

  test "returns {:error, body} when API returns status code > 299" do
    mock(fn
      %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 307,
          body: %{message: "Redirected"}
        }
    end)

    assert {:error, %{status: 307, body: %{message: "Redirected"}}} =
             ApiClient.onboard_to_kaapi(@params)
  end

  test "returns {:error, msg} when API returns error status code without error field" do
    mock(fn
      %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 404,
          body: %{message: "Not Found"}
        }
    end)

    assert {:error, %{status: 404, body: %{message: "Not Found"}}} =
             ApiClient.onboard_to_kaapi(@params)
  end

  test "returns {:error, msg} when API transport fails" do
    mock(fn
      %Tesla.Env{method: :post} ->
        {:error, :timeout}
    end)

    assert {:error, :timeout} = ApiClient.onboard_to_kaapi(@params)
  end

  describe "create_assistant/2" do
    test "successfully creates assistant in kaapi" do
      params = %{
        name: "Assistant-f11ead89",
        instructions: "this is a story telling assistant that tells story",
        id: "asst_123",
        model: "gpt-4o",
        temperature: 1.0
      }

      mock(fn
        %Tesla.Env{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{
              error: nil,
              data: %{
                id: 86,
                name: "Assistant-f78f4392",
                instructions: "you are a helpful asssitant",
                organization_id: 1,
                project_id: 1,
                assistant_id: "asst_5TtScw1DwabcDBjvrvY",
                vector_store_ids: [],
                temperature: 0.1,
                model: "gpt-4o",
                is_deleted: false,
                deleted_at: nil
              },
              metadata: nil,
              success: true
            }
          }
      end)

      assert {:ok, resp} = ApiClient.create_assistant(params, @org_kaapi_api_key)
      assert resp.data.name == "Assistant-f78f4392"
      assert resp.data.assistant_id == "asst_5TtScw1DwabcDBjvrvY"
    end

    test "returns error if Kaapi fails" do
      params = %{
        name: "Repeated-Assistant-f11ead89",
        instructions: "this is a story telling assistant that tells story",
        id: "asst_123",
        model: "gpt-4o",
        temperature: 1.0
      }

      response_body = %{
        error: "Assistant already exists",
        data: %{},
        metadata: nil,
        success: true
      }

      mock(fn
        %Tesla.Env{method: :post} ->
          %Tesla.Env{
            status: 409,
            body: response_body
          }
      end)

      assert {:error, %{status: 409, body: ^response_body}} =
               ApiClient.create_assistant(params, @org_kaapi_api_key)
    end
  end

  describe "update_assistant/3" do
    test "successfully updates assistant in kaapi" do
      mock(fn
        %Tesla.Env{
          method: :patch
        } ->
          %Tesla.Env{
            status: 200,
            body: %{
              error: nil,
              data: %{
                id: 86,
                name: "Assistant-f78f4392",
                instructions: "you are a helpful asssitant",
                organization_id: 1,
                project_id: 1,
                assistant_id: "asst_5TtScw1DwabcDBjvrvY",
                vector_store_ids: ["vs_1"],
                temperature: 0.1,
                model: "gpt-4o",
                is_deleted: false,
                deleted_at: nil
              },
              metadata: nil,
              success: true
            }
          }
      end)

      params = %{
        name: "Updated Assistant",
        model: "gpt-4o",
        instructions: "new instructions",
        temperature: 0.7,
        tool_resources: %{file_search: %{vector_store_ids: ["vs_1"]}}
      }

      assert {:ok, resp} =
               ApiClient.update_assistant("asst_5TtScw1DwabcDBjvrvY", params, @org_kaapi_api_key)

      assert resp.data.assistant_id == "asst_5TtScw1DwabcDBjvrvY"
      assert resp.data.vector_store_ids == ["vs_1"]
    end

    test "update assistant with invalid id" do
      params = %{
        name: "Updated Assistant",
        model: "gpt-4o",
        instructions: "new instructions",
        temperature: 0.7,
        tool_resources: %{file_search: %{vector_store_ids: ["vs_1"]}}
      }

      mock(fn %Tesla.Env{method: :patch} ->
        %Tesla.Env{status: 404, body: %{error: "Not Found", data: %{}}}
      end)

      assert {:error, %{status: 404, body: %{error: "Not Found", data: %{}}}} =
               ApiClient.update_assistant("invalid_id", params, @org_kaapi_api_key)
    end
  end

  describe "create_collection/2" do
    test "successfully creates a collection in kaapi" do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            success: true,
            data: %{
              job_id: "2b55b30c-f2c8-4772-a0fd-4a0e7d0e0803",
              status: "PROCESSING",
              action_type: "CREATE",
              collection: nil,
              error_message: nil
            },
            error: nil,
            metadata: nil
          }
        }
      end)

      params = %{callback_url: "https://example.com/callback", file_ids: ["file_1", "file_2"]}

      assert {:ok, resp} = ApiClient.create_collection(params, @org_kaapi_api_key)
      assert resp.data.job_id == "2b55b30c-f2c8-4772-a0fd-4a0e7d0e0803"
      assert resp.data.status == "PROCESSING"
      assert resp.data.action_type == "CREATE"
      assert resp.data.collection == nil
      assert resp.data.error_message == nil
    end

    test "returns error when kaapi returns error status" do
      response_body = %{error: "Invalid parameters", data: %{}, success: false}

      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 422, body: response_body}
      end)

      params = %{name: "Test Collection"}

      assert {:error, %{status: 422, body: ^response_body}} =
               ApiClient.create_collection(params, @org_kaapi_api_key)
    end

    test "returns error on timeout" do
      mock(fn %Tesla.Env{method: :post} ->
        {:error, :timeout}
      end)

      params = %{callback_url: "http://example.com/callback", file_ids: ["file_1"]}

      assert {:error, :timeout} = ApiClient.create_collection(params, @org_kaapi_api_key)
    end
  end

  describe "get_collection_status/2" do
    test "successfully gets collection status" do
      mock(fn %Tesla.Env{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            success: true,
            data: %{
              status: "SUCCESSFUL"
            }
          }
        }
      end)

      assert {:ok, %{data: %{status: "SUCCESSFUL"}, success: true}} =
               ApiClient.get_collection_status("job_3fa85f64", @org_kaapi_api_key)
    end

    test "returns error for failures" do
      mock(fn %Tesla.Env{method: :get} ->
        %Tesla.Env{
          status: 400,
          body: %{
            success: false,
            error: %{
              message: "Invalid request"
            }
          }
        }
      end)

      assert {:error,
              %{status: 400, body: %{success: false, error: %{message: "Invalid request"}}}} =
               ApiClient.get_collection_status("job_3fa85f64", @org_kaapi_api_key)
    end
  end

  describe "get_document/2" do
    test "returns document data with signed_url" do
      mock(fn %Tesla.Env{method: :get, query: query} ->
        assert query[:include_url] == "true"

        %Tesla.Env{
          status: 200,
          body: %{
            success: true,
            data: %{
              id: "96331afd-7f06-4a46-ac4d-0a65c6fd1b1e",
              fname: "biu-1.pdf",
              project_id: 1,
              signed_url: "https://kaapi-test.s3.amazonaws.com/test/biu-1.pdf"
            }
          }
        }
      end)

      assert {:ok, %{success: true, data: data}} =
               ApiClient.get_document("96331afd-7f06-4a46-ac4d-0a65c6fd1b1e", @org_kaapi_api_key)

      assert data.fname == "biu-1.pdf"
      assert data.signed_url == "https://kaapi-test.s3.amazonaws.com/test/biu-1.pdf"
    end

    test "returns error when document is not found" do
      mock(fn %Tesla.Env{method: :get} ->
        %Tesla.Env{status: 404, body: %{error: "Not Found"}}
      end)

      assert {:error, %{status: 404, body: %{error: "Not Found"}}} =
               ApiClient.get_document("missing_doc", @org_kaapi_api_key)
    end

    test "returns error on timeout" do
      mock(fn %Tesla.Env{method: :get} -> {:error, :timeout} end)

      assert {:error, :timeout} = ApiClient.get_document("doc_1", @org_kaapi_api_key)
    end
  end

  describe "create_config_version/3" do
    test "successfully creates config version in kaapi" do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            success: true,
            data: %{
              config_blob: %{
                completion: %{
                  model: "gpt-4o-mini",
                  instructions: "You are a helpful assistant",
                  temperature: 1.0,
                  knowledge_base_ids: ["vs_3fa85f64"]
                }
              },
              id: "3fa85f64-5717-4562-b3fc-2c963f66afa6",
              config_id: "3fa85f64-5717-4562-b3fc-2c963f66afa6",
              version: 1,
              inserted_at: "2026-02-25T10:55:11.678Z",
              updated_at: "2026-02-25T10:55:11.678Z"
            },
            metadata: %{}
          }
        }
      end)

      config_id = "3fa85f64-5717-4562-b3fc-2c963f66afa6"

      body =
        %{
          completion: %{
            model: "gpt-4o-mini",
            instructions: "You are a helpful assistant",
            temperature: 1.0,
            knowledge_base_ids: ["vs_3fa85f64"]
          }
        }

      assert {:ok, resp} =
               ApiClient.create_config_version(config_id, body, @org_kaapi_api_key)

      assert resp.data.config_id == "3fa85f64-5717-4562-b3fc-2c963f66afa6"
      assert resp.data.version == 1
    end

    test "returns error when kaapi returns error status" do
      response_body = %{error: "Invalid parameters", data: %{}, success: false}

      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 422, body: response_body}
      end)

      config_id = "config_123"
      body = %{name: "Test Config Version"}

      assert {:error, %{status: 422, body: ^response_body}} =
               ApiClient.create_config_version(config_id, body, @org_kaapi_api_key)
    end

    test "returns error on timeout" do
      mock(fn %Tesla.Env{method: :post} ->
        {:error, :timeout}
      end)

      config_id = "config_123"
      body = %{name: "Test Config Version"}

      assert {:error, :timeout} =
               ApiClient.create_config_version(config_id, body, @org_kaapi_api_key)
    end
  end

  describe "delete_assistant/1" do
    test "successfully updates assistant in kaapi" do
      mock(fn %Tesla.Env{method: :delete} ->
        %Tesla.Env{
          status: 200,
          body: %{error: nil, data: "Deleted", metadata: nil, success: true}
        }
      end)

      assert {:ok, resp} =
               ApiClient.delete_assistant("asst_5TtScw1DwabcDBjvrvY", @org_kaapi_api_key)

      assert resp.data == "Deleted"
    end

    test "update assistant with invalid id" do
      mock(fn %Tesla.Env{method: :delete} ->
        %Tesla.Env{status: 404, body: %{error: "Not Found", data: %{}}}
      end)

      assert {:error, %{status: 404, body: %{error: "Not Found", data: %{}}}} =
               ApiClient.delete_assistant("invalid_id", @org_kaapi_api_key)
    end
  end

  describe "get_evaluation_scores/2" do
    test "returns all evaluator scores including LLM-as-a-Judge on 200" do
      mock(fn %Tesla.Env{method: :get, query: query} ->
        assert query[:get_trace_info] == "true"

        %Tesla.Env{
          status: 200,
          body: %{
            data: %{
              id: 42,
              status: "completed",
              summary_scores: [
                %{
                  avg: 0.56,
                  std: 0.12,
                  name: "cosine_similarity",
                  data_type: "NUMERIC",
                  total_pairs: 25
                },
                %{
                  avg: 0.69,
                  std: 0.28,
                  name: "Correctness(LLM-as-a-Judge)",
                  data_type: "NUMERIC",
                  total_pairs: 25
                }
              ]
            }
          }
        }
      end)

      assert {:ok, resp} = ApiClient.get_evaluation_scores(42, @org_kaapi_api_key)
      assert resp.data.status == "completed"
      assert length(resp.data.summary_scores) == 2
      llm_score = Enum.find(resp.data.summary_scores, &(&1.name == "Correctness(LLM-as-a-Judge)"))
      assert llm_score.avg == 0.69
    end

    test "returns error when evaluation is not found" do
      mock(fn %Tesla.Env{method: :get} ->
        %Tesla.Env{status: 404, body: %{error: "Evaluation not found"}}
      end)

      assert {:error, %{status: 404, body: %{error: "Evaluation not found"}}} =
               ApiClient.get_evaluation_scores(999, @org_kaapi_api_key)
    end

    test "returns error on 500 from Kaapi" do
      mock(fn %Tesla.Env{method: :get} ->
        %Tesla.Env{status: 500, body: %{error: "Internal server error"}}
      end)

      assert {:error, %{status: 500, body: %{error: "Internal server error"}}} =
               ApiClient.get_evaluation_scores(42, @org_kaapi_api_key)
    end
  end

  describe "list_models/2" do
    test "returns the model page and sends provider/skip/limit as query params" do
      mock(fn %Tesla.Env{method: :get, query: query} ->
        assert query[:provider] == "openai"
        assert query[:skip] == 0
        assert query[:limit] == 100

        %Tesla.Env{
          status: 200,
          body: %{
            data: %{data: [%{provider: "openai", model_name: "gpt-4o"}]},
            metadata: %{has_more: false}
          }
        }
      end)

      assert {:ok, %{data: %{data: [model]}, metadata: %{has_more: false}}} =
               ApiClient.list_models(%{provider: "openai"}, @org_kaapi_api_key)

      assert model.model_name == "gpt-4o"
    end

    test "returns error tuple on 422 from Kaapi" do
      mock(fn %Tesla.Env{method: :get} ->
        %Tesla.Env{status: 422, body: %{error: "Invalid provider"}}
      end)

      assert {:error, %{status: 422, body: %{error: "Invalid provider"}}} =
               ApiClient.list_models(%{provider: "openai"}, @org_kaapi_api_key)
    end
  end

  describe "upload_evaluation_dataset/2" do
    setup [:create_dataset_upload_params]

    test "successfully uploads the dataset to the v1 endpoint", %{dataset_params: dataset_params} do
      mock(fn %Tesla.Env{method: :post, url: url} ->
        assert url =~ "/api/v1/evaluations/datasets"

        %Tesla.Env{
          status: 200,
          body: %{data: %{dataset_name: "valid_dataset", dataset_id: "88001"}}
        }
      end)

      assert {:ok, %{data: %{dataset_id: "88001"}}} =
               ApiClient.upload_evaluation_dataset(dataset_params, @org_kaapi_api_key)
    end

    test "returns error when kaapi returns error status", %{dataset_params: dataset_params} do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 422, body: %{error: "Invalid dataset format"}}
      end)

      assert {:error, %{status: 422, body: %{error: "Invalid dataset format"}}} =
               ApiClient.upload_evaluation_dataset(dataset_params, @org_kaapi_api_key)
    end

    test "returns error on transport failure/timeout", %{dataset_params: dataset_params} do
      mock(fn %Tesla.Env{method: :post} -> {:error, :timeout} end)

      assert {:error, :timeout} =
               ApiClient.upload_evaluation_dataset(dataset_params, @org_kaapi_api_key)
    end
  end

  describe "upload_evaluation_dataset_v2/2" do
    setup [:create_dataset_upload_params]

    test "successfully uploads the dataset to the v2 endpoint", %{dataset_params: dataset_params} do
      mock(fn %Tesla.Env{method: :post, url: url} ->
        assert url =~ "/api/v2/evaluations/datasets"

        %Tesla.Env{
          status: 200,
          body: %{data: %{dataset_id: "99001", total_items: 42}}
        }
      end)

      assert {:ok, %{data: %{dataset_id: "99001", total_items: 42}}} =
               ApiClient.upload_evaluation_dataset_v2(dataset_params, @org_kaapi_api_key)
    end

    test "returns error when kaapi returns error status", %{dataset_params: dataset_params} do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 500, body: %{error: "Internal server error"}}
      end)

      assert {:error, %{status: 500, body: %{error: "Internal server error"}}} =
               ApiClient.upload_evaluation_dataset_v2(dataset_params, @org_kaapi_api_key)
    end

    test "returns error on transport failure/timeout", %{dataset_params: dataset_params} do
      mock(fn %Tesla.Env{method: :post} -> {:error, :timeout} end)

      assert {:error, :timeout} =
               ApiClient.upload_evaluation_dataset_v2(dataset_params, @org_kaapi_api_key)
    end
  end

  describe "create_evaluation_v2/2" do
    @evaluation_params %{
      experiment_name: "antaratrial",
      config_id: "d186d8eb-1211-4a7b-aa28-e8a22f8163c9",
      config_version: 7,
      dataset_id: 651
    }

    test "successfully creates an evaluation on the v2 endpoint" do
      mock(fn %Tesla.Env{method: :post, url: url} ->
        assert url =~ "/api/v2/evaluations"

        %Tesla.Env{
          status: 200,
          body: %{data: %{id: 777, run_name: "antaratrial", status: "processing"}}
        }
      end)

      assert {:ok, %{data: %{id: 777, status: "processing"}}} =
               ApiClient.create_evaluation_v2(@evaluation_params, @org_kaapi_api_key)
    end

    test "returns error when kaapi returns error status" do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 422, body: %{error: "Invalid config_id"}}
      end)

      assert {:error, %{status: 422, body: %{error: "Invalid config_id"}}} =
               ApiClient.create_evaluation_v2(@evaluation_params, @org_kaapi_api_key)
    end

    test "returns error on transport failure/timeout" do
      mock(fn %Tesla.Env{method: :post} -> {:error, :timeout} end)

      assert {:error, :timeout} =
               ApiClient.create_evaluation_v2(@evaluation_params, @org_kaapi_api_key)
    end
  end

  describe "improve_prompt_v2/3" do
    test "successfully dispatches the v2 improve-prompt request" do
      mock(fn %Tesla.Env{method: :post, url: url} ->
        assert url =~ "/api/v2/evaluations/767/improve-prompt"

        %Tesla.Env{
          status: 200,
          body: %{
            success: true,
            data: %{
              job_id: "a8f2be70-4ac6-42af-ada7-c28ac46fd834",
              status: "PENDING",
              message: "Prompt recommendation is running"
            },
            error: nil
          }
        }
      end)

      body = %{callback_url: "https://example.com/kaapi/improve_prompt"}

      assert {:ok, resp} = ApiClient.improve_prompt_v2(767, body, @org_kaapi_api_key)
      assert resp.data.job_id == "a8f2be70-4ac6-42af-ada7-c28ac46fd834"
      assert resp.data.status == "PENDING"
    end

    test "returns error when kaapi returns error status" do
      response_body = %{error: "Evaluation not found", data: %{}, success: false}

      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 404, body: response_body}
      end)

      assert {:error, %{status: 404, body: ^response_body} = error} =
               ApiClient.improve_prompt_v2(
                 999,
                 %{callback_url: "https://example.com"},
                 @org_kaapi_api_key
               )

      assert error.body.error == "Evaluation not found"
    end

    test "returns error on timeout" do
      mock(fn %Tesla.Env{method: :post} -> {:error, :timeout} end)

      assert {:error, :timeout} =
               ApiClient.improve_prompt_v2(
                 767,
                 %{callback_url: "https://example.com"},
                 @org_kaapi_api_key
               )
    end
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
