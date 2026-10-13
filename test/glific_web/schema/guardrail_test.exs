defmodule GlificWeb.Schema.GuardrailTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{Fixtures, Partners}

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

  test "guardrailValidators returns validator types with their schemas", %{manager: user} do
    Tesla.Mock.mock(fn %{method: :get, url: url} ->
      assert String.ends_with?(url, "/api/v1/guardrails")

      %Tesla.Env{
        status: 200,
        body: %{validators: [%{type: "pii_remover", config: %{title: "PIIRemover"}}]}
      }
    end)

    {:ok, query_data} = auth_query_gql_by(:list_validators, user, variables: %{})

    assert [%{"type" => "pii_remover", "config" => config}] =
             get_in(query_data, [:data, "guardrailValidators", "validators"])

    assert Jason.decode!(config) == %{"title" => "PIIRemover"}
  end

  test "guardrailValidators returns the error of a failed Kaapi response", %{manager: user} do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{status: 200, body: %{success: false, error: "Failed to retrieve schema"}}
    end)

    {:ok, query_data} = auth_query_gql_by(:list_validators, user, variables: %{})

    assert [%{"message" => "Failed to retrieve schema"}] =
             get_in(query_data, [:data, "guardrailValidators", "errors"])
  end

  test "guardrailValidators surfaces a Kaapi HTTP error detail", %{manager: user} do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{status: 500, body: %{detail: "Guardrails service unavailable"}}
    end)

    {:ok, query_data} = auth_query_gql_by(:list_validators, user, variables: %{})

    assert [%{"message" => "Guardrails service unavailable"}] =
             get_in(query_data, [:data, "guardrailValidators", "errors"])
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

    assert [%{"message" => "Kaapi is not active"}] =
             get_in(query_data, [:data, "guardrailValidators", "errors"])
  end
end
