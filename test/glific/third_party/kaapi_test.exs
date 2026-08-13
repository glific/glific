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
