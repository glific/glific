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

  @doc_links %{
    "gender_assumption_bias" =>
      "https://projecttech4devai.github.io/kaapi-docs/guardrails/gender-neutrality",
    "uli_slur_match" =>
      "https://projecttech4devai.github.io/kaapi-docs/guardrails/content-safety",
    "pii_remover" =>
      "https://projecttech4devai.github.io/kaapi-docs/guardrails/privacy-protection",
    "topic_relevance_llm" =>
      "https://projecttech4devai.github.io/kaapi-docs/guardrails/scope-control"
  }

  defp mock_kaapi_response(status, body) do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: status,
        headers: [{"content-type", "application/json"}],
        body: Jason.encode!(body)
      }
    end)
  end

  test "guardrailValidators returns only supported validator types with their schema and doc link",
       %{manager: user} do
    Tesla.Mock.mock(fn %{method: :get, url: url, headers: headers} ->
      assert String.ends_with?(url, "/api/v1/guardrails")
      assert {"X-API-KEY", "sk_test_key"} in headers

      validators =
        for type <- [
              "profanity_free",
              "gender_assumption_bias",
              "uli_slur_match",
              "llm_critic",
              "pii_remover",
              "topic_relevance_llm"
            ],
            do: %{"type" => type, "config" => @schema}

      %Tesla.Env{
        status: 200,
        headers: [{"content-type", "application/json"}],
        body: Jason.encode!(%{"validators" => validators})
      }
    end)

    {:ok, query_data} = auth_query_gql_by(:list_validators, user, variables: %{})
    validators = get_in(query_data, [:data, "guardrailValidators", "validators"])

    assert Enum.map(validators, & &1["type"]) ==
             ["gender_assumption_bias", "uli_slur_match", "pii_remover", "topic_relevance_llm"]

    for validator <- validators do
      assert validator["link"] == @doc_links[validator["type"]]
      assert Jason.decode!(validator["config"]) == @schema
    end
  end

  test "guardrailValidators returns the error of a failed Kaapi response", %{manager: user} do
    mock_kaapi_response(401, %{success: false, error: "Invalid API key"})

    {:ok, query_data} = auth_query_gql_by(:list_validators, user, variables: %{})

    assert [%{message: "Invalid API key"}] = query_data.errors
  end

  test "guardrailValidators returns a generic error when Kaapi's error body has no message",
       %{manager: user} do
    mock_kaapi_response(422, %{detail: [%{msg: "field required"}]})

    {:ok, query_data} = auth_query_gql_by(:list_validators, user, variables: %{})

    assert [%{message: "An unknown error occurred, please contact Glific support."}] =
             query_data.errors
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

  test "returns unauthorized for a user below staff role" do
    user = Fixtures.user_fixture(%{roles: ["none"]})

    {:ok, query_data} = auth_query_gql_by(:list_validators, user, variables: %{})

    assert [%{message: "Unauthorized"}] = query_data.errors
  end
end
