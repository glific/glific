defmodule Glific.ThirdParty.KaapiTest do
  use GlificWeb.ConnCase
  import Tesla.Mock
  alias Glific.Partners
  alias Glific.ThirdParty.Kaapi

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
        completion_params = Jason.decode!(body)["config_blob"]["completion"]["params"]

        assert completion_params == %{
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

      assert {:ok, _result} = Kaapi.create_assistant_config(params, 1)
    end

    test "forwards effort/summary settings for a reasoning model, without a stray temperature" do
      mock(fn %Tesla.Env{method: :post, body: body} ->
        completion_params = Jason.decode!(body)["config_blob"]["completion"]["params"]

        assert completion_params == %{
                 "model" => "gpt-5.1",
                 "instructions" => "You are a helpful assistant",
                 "knowledge_base_ids" => [],
                 "effort" => "none",
                 "summary" => "auto"
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
        settings: %{"effort" => "none", "summary" => "auto"}
      }

      assert {:ok, _result} = Kaapi.create_assistant_config(params, 1)
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
