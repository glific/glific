defmodule GlificWeb.Schema.GuardrailTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{Fixtures, Partners}

  @schema %{
    "$defs" => %{"Stage" => %{"enum" => ["input", "output"]}},
    "properties" => %{"stage" => %{"$ref" => "#/$defs/Stage"}},
    "required" => ["type"]
  }

  load_gql(:list_validators, GlificWeb.Schema, "assets/gql/guardrails/list_validators.gql")

  setup %{organization_id: organization_id} do
    FunWithFlags.enable(:is_ai_guardrail_enabled, for_actor: %{organization_id: organization_id})

    Partners.create_credential(%{
      organization_id: organization_id,
      shortcode: "kaapi",
      keys: %{},
      secrets: %{"api_key" => "sk_test_key"},
      is_active: true
    })

    :ok
  end

  test "guardrailValidators returns only supported validator types with their schema and doc link",
       %{
         manager: user
       } do
    Tesla.Mock.mock(fn %{method: :get, url: url, headers: headers} ->
      assert String.ends_with?(url, "/api/v1/guardrails")
      assert {"X-API-KEY", "sk_test_key"} in headers

      validators =
        for type <- ["uli_slur_match", "pii_remover", "llm_critic", "profanity_free"],
            do: %{"type" => type, "config" => @schema}

      %Tesla.Env{
        status: 200,
        headers: [{"content-type", "application/json"}],
        body: Jason.encode!(%{"validators" => validators})
      }
    end)

    {:ok, query_data} = auth_query_gql_by(:list_validators, user, variables: %{})

    assert [
             %{
               "type" => "pii_remover",
               "config" => pii_config,
               "link" =>
                 "https://projecttech4devai.github.io/kaapi-docs/guardrails/privacy-protection"
             },
             %{
               "type" => "profanity_free",
               "config" => profanity_config,
               "link" =>
                 "https://projecttech4devai.github.io/kaapi-docs/guardrails/content-safety"
             }
           ] = get_in(query_data, [:data, "guardrailValidators", "validators"])

    assert Jason.decode!(pii_config) == @schema
    assert Jason.decode!(profanity_config) == @schema
  end

  test "guardrailValidators returns the error of a failed Kaapi response", %{manager: user} do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{status: 500, body: %{success: false, error: "Failed to retrieve schema"}}
    end)

    {:ok, query_data} = auth_query_gql_by(:list_validators, user, variables: %{})

    assert [%{message: "Failed to retrieve schema"}] = query_data.errors
  end

  test "guardrailValidators returns a retry message when Kaapi times out", %{manager: user} do
    Tesla.Mock.mock(fn %{method: :get} -> {:error, :timeout} end)

    {:ok, query_data} = auth_query_gql_by(:list_validators, user, variables: %{})

    assert [%{message: "Timeout occurred, please try again."}] = query_data.errors
  end

  test "returns an error when the feature flag is disabled for the organization" do
    organization = Fixtures.organization_fixture()
    user = Fixtures.user_fixture(%{organization_id: organization.id})

    {:ok, query_data} = auth_query_gql_by(:list_validators, user, variables: %{})

    assert [%{message: "AI Guardrails is not enabled for the organization."}] = query_data.errors
  end

  test "returns an error when Kaapi is not active for the organization" do
    organization = Fixtures.organization_fixture()
    user = Fixtures.user_fixture(%{organization_id: organization.id})
    FunWithFlags.enable(:is_ai_guardrail_enabled, for_actor: %{organization_id: organization.id})

    {:ok, query_data} = auth_query_gql_by(:list_validators, user, variables: %{})

    assert [%{message: "Kaapi is not active"}] = query_data.errors
  end
end
