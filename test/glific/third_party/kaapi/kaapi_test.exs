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

  @org_kaapi_api_key "sk_3fa22108-f464-41e5-81d9-d8a298854430"

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
end
