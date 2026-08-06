defmodule Glific.ThirdParty.Kaapi.LlmCallTest do
  use Glific.DataCase
  import Tesla.Mock

  alias Glific.Fixtures
  alias Glific.Partners
  alias Glific.ThirdParty.Kaapi

  @org_id 1
  @api_key "sk_test_key"

  @payload %{
    query: %{input: "Hello", conversation: %{auto_create: true}},
    config: %{id: "kaapi_uuid", version: 1},
    callback_url: "https://api.glific.glific.com/kaapi/llm_call",
    request_metadata: %{request_id: "req-1", user_id: 9}
  }

  setup do
    {:ok, _credential} =
      Partners.create_credential(%{
        organization_id: @org_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{"api_key" => @api_key},
        is_active: true
      })

    Partners.get_organization!(@org_id) |> Partners.fill_cache()
    :ok
  end

  describe "llm_call/2" do
    test "returns job_id and conversation_id on a successful dispatch" do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{data: %{job_id: "job_001", conversation: %{id: "conv_001"}}}
        }
      end)

      assert {:ok, %{job_id: "job_001", conversation_id: "conv_001"}} =
               Kaapi.llm_call(@payload, @org_id)
    end

    test "returns nil conversation_id when Kaapi doesn't echo one back" do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 200, body: %{data: %{job_id: "job_002"}}}
      end)

      assert {:ok, %{job_id: "job_002", conversation_id: nil}} =
               Kaapi.llm_call(@payload, @org_id)
    end

    test "returns an error for an unexpected 2xx body shape" do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 200, body: %{unexpected: "shape"}}
      end)

      assert {:error, _reason} = Kaapi.llm_call(@payload, @org_id)
    end

    test "returns an error when Kaapi responds with a failure status" do
      mock(fn %Tesla.Env{method: :post} ->
        %Tesla.Env{status: 422, body: %{error: "invalid config"}}
      end)

      assert {:error, _reason} = Kaapi.llm_call(@payload, @org_id)
    end

    test "returns an error when Kaapi is not configured for the org" do
      organization = Fixtures.organization_fixture()
      assert {:error, "Kaapi is not active"} = Kaapi.llm_call(@payload, organization.id)
    end
  end
end
