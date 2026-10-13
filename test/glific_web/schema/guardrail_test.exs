defmodule GlificWeb.Schema.GuardrailTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{Fixtures, Partners}

  @guardrail_defs %{
    "GuardrailOnFail" => %{
      "enum" => ["exception", "fix", "rephrase"],
      "title" => "GuardrailOnFail",
      "type" => "string"
    },
    "Stage" => %{"enum" => ["input", "output"], "title" => "Stage", "type" => "string"}
  }

  @base_properties %{
    "on_fail" => %{"$ref" => "#/$defs/GuardrailOnFail", "default" => "fix"},
    "stage" => %{
      "anyOf" => [%{"$ref" => "#/$defs/Stage"}, %{"type" => "null"}],
      "default" => nil
    }
  }

  @validators [
    %{
      "type" => "uli_slur_match",
      "config" => %{
        "$defs" => @guardrail_defs,
        "additionalProperties" => false,
        "properties" =>
          Map.merge(@base_properties, %{
            "type" => %{"const" => "uli_slur_match", "title" => "Type", "type" => "string"},
            "languages" => %{
              "default" => ["en", "hi"],
              "items" => %{"type" => "string"},
              "title" => "Languages",
              "type" => "array"
            },
            "severity" => %{
              "default" => "all",
              "enum" => ["low", "medium", "high", "all"],
              "title" => "Severity",
              "type" => "string"
            }
          }),
        "required" => ["type"],
        "title" => "LexicalSlurSafetyValidatorConfig",
        "type" => "object"
      }
    },
    %{
      "type" => "llm_critic",
      "config" => %{
        "$defs" => @guardrail_defs,
        "additionalProperties" => false,
        "properties" =>
          Map.merge(@base_properties, %{
            "type" => %{"const" => "llm_critic", "title" => "Type", "type" => "string"},
            "metrics" => %{
              "additionalProperties" => true,
              "title" => "Metrics",
              "type" => "object"
            },
            "max_score" => %{"title" => "Max Score", "type" => "integer"},
            "llm_callable" => %{"title" => "Llm Callable", "type" => "string"}
          }),
        "required" => ["type", "metrics", "max_score", "llm_callable"],
        "title" => "LLMCriticSafetyValidatorConfig",
        "type" => "object"
      }
    },
    %{
      "type" => "profanity_free",
      "config" => %{
        "$defs" => @guardrail_defs,
        "additionalProperties" => false,
        "properties" =>
          Map.put(@base_properties, "type", %{
            "const" => "profanity_free",
            "title" => "Type",
            "type" => "string"
          }),
        "required" => ["type"],
        "title" => "ProfanityFreeSafetyValidatorConfig",
        "type" => "object"
      }
    }
  ]

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

  test "guardrailValidators returns only supported validator types with their config JSON schema",
       %{
         manager: user
       } do
    Tesla.Mock.mock(fn %{method: :get, url: url, headers: headers} ->
      assert String.ends_with?(url, "/api/v1/guardrails")
      assert {"X-API-KEY", "sk_test_key"} in headers

      %Tesla.Env{
        status: 200,
        headers: [{"content-type", "application/json"}],
        body: Jason.encode!(%{"validators" => @validators})
      }
    end)

    {:ok, query_data} = auth_query_gql_by(:list_validators, user, variables: %{})

    validators = get_in(query_data, [:data, "guardrailValidators", "validators"])

    assert Enum.map(validators, & &1["type"]) == ["uli_slur_match", "profanity_free"]

    supported_schemas =
      for %{"type" => type, "config" => config} <- @validators,
          type in ["uli_slur_match", "profanity_free"],
          do: config

    assert Enum.map(validators, &Jason.decode!(&1["config"])) == supported_schemas

    assert [slur_schema, profanity_schema] = Enum.map(validators, &Jason.decode!(&1["config"]))
    assert slur_schema["required"] == ["type"]
    assert slur_schema["properties"]["severity"]["enum"] == ["low", "medium", "high", "all"]
    assert slur_schema["$defs"]["GuardrailOnFail"]["enum"] == ["exception", "fix", "rephrase"]
    assert profanity_schema["$defs"]["Stage"]["enum"] == ["input", "output"]
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
