defmodule GlificWeb.Schema.GuardrailTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{Fixtures, Partners}

  @config_id "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
  @configs_path "/api/v1/guardrails/validators/configs"

  @kaapi_config %{
    id: @config_id,
    name: "Block slurs",
    type: "uli_slur_match",
    stage: "input",
    on_fail_action: "fix",
    is_enabled: true,
    organization_id: 1,
    project_id: 1,
    inserted_at: "2026-10-12T10:00:00",
    updated_at: "2026-10-12T10:00:00",
    severity: "all",
    languages: ["en", "hi"]
  }

  load_gql(:list_validators, GlificWeb.Schema, "assets/gql/guardrails/list_validators.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/guardrails/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/guardrails/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/guardrails/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/guardrails/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/guardrails/delete.gql")

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

  test "guardrailConfigs sends ids as repeated params and drops empty filters", %{manager: user} do
    other_id = Ecto.UUID.generate()

    Tesla.Mock.mock(fn %{method: :get, url: url, query: query} ->
      assert String.ends_with?(url, @configs_path)
      assert query == [ids: @config_id, ids: other_id, stage: "input"]

      %Tesla.Env{status: 200, body: %{success: true, data: [@kaapi_config]}}
    end)

    {:ok, query_data} =
      auth_query_gql_by(
        :list,
        user,
        variables: %{"filter" => %{"ids" => [@config_id, other_id], "stage" => "input"}}
      )

    assert [config] = get_in(query_data, [:data, "guardrailConfigs", "guardrailConfigs"])
    assert config["id"] == @config_id
    assert config["onFailAction"] == "fix"
    assert Jason.decode!(config["config"]) == %{"severity" => "all", "languages" => ["en", "hi"]}
  end

  test "guardrailConfig returns the config with validator-specific keys split out", %{
    manager: user
  } do
    Tesla.Mock.mock(fn %{method: :get, url: url} ->
      assert String.ends_with?(url, "#{@configs_path}/#{@config_id}")
      %Tesla.Env{status: 200, body: %{success: true, data: @kaapi_config}}
    end)

    {:ok, query_data} = auth_query_gql_by(:by_id, user, variables: %{"id" => @config_id})

    config = get_in(query_data, [:data, "guardrailConfig", "guardrailConfig"])
    assert config["name"] == "Block slurs"
    assert config["isEnabled"] == true
    assert config["insertedAt"] == "2026-10-12T10:00:00"
    assert Jason.decode!(config["config"]) == %{"severity" => "all", "languages" => ["en", "hi"]}
  end

  test "guardrailConfig rejects an id that is not a UUID without calling Kaapi", %{
    manager: user
  } do
    {:ok, query_data} = auth_query_gql_by(:by_id, user, variables: %{"id" => "1"})

    assert [%{"message" => "Invalid guardrail config id."}] =
             get_in(query_data, [:data, "guardrailConfig", "errors"])
  end

  test "guardrailConfig maps a bare Kaapi 404 to not found", %{manager: user} do
    Tesla.Mock.mock(fn %{method: :get} -> %Tesla.Env{status: 404, body: %{}} end)

    {:ok, query_data} = auth_query_gql_by(:by_id, user, variables: %{"id" => @config_id})

    assert [%{"message" => "Guardrail config not found."}] =
             get_in(query_data, [:data, "guardrailConfig", "errors"])
  end

  test "createGuardrailConfig sends base fields and config as one flat body", %{manager: user} do
    Tesla.Mock.mock(fn %{method: :post, url: url, body: body} ->
      assert String.ends_with?(url, @configs_path)

      assert Jason.decode!(body) == %{
               "name" => "Block slurs",
               "type" => "uli_slur_match",
               "stage" => "input",
               "severity" => "all",
               "languages" => ["en", "hi"]
             }

      %Tesla.Env{status: 200, body: %{success: true, data: @kaapi_config}}
    end)

    {:ok, query_data} =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "name" => "Block slurs",
            "type" => "uli_slur_match",
            "stage" => "input",
            "config" =>
              Jason.encode!(%{severity: "all", languages: ["en", "hi"], name: "ignored"})
          }
        }
      )

    assert %{"id" => @config_id} =
             get_in(query_data, [:data, "createGuardrailConfig", "guardrailConfig"])
  end

  test "createGuardrailConfig surfaces Kaapi validation errors", %{manager: user} do
    Tesla.Mock.mock(fn %{method: :post} ->
      %Tesla.Env{
        status: 422,
        body: %{
          detail: [%{loc: ["body", "name"], msg: "String should have at least 5 characters"}]
        }
      }
    end)

    {:ok, query_data} =
      auth_query_gql_by(:create, user,
        variables: %{"input" => %{"name" => "abc", "type" => "pii_remover", "stage" => "input"}}
      )

    assert [%{"message" => "name: String should have at least 5 characters"}] =
             get_in(query_data, [:data, "createGuardrailConfig", "errors"])
  end

  test "createGuardrailConfig surfaces Kaapi's error message", %{manager: user} do
    Tesla.Mock.mock(fn %{method: :post} ->
      %Tesla.Env{status: 400, body: %{success: false, error: "Validator already exists"}}
    end)

    {:ok, query_data} =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{"name" => "PII guard", "type" => "pii_remover", "stage" => "input"}
        }
      )

    assert [%{"message" => "Validator already exists"}] =
             get_in(query_data, [:data, "createGuardrailConfig", "errors"])
  end

  test "createGuardrailConfig surfaces a Kaapi HTTP error detail", %{manager: user} do
    Tesla.Mock.mock(fn %{method: :post} ->
      %Tesla.Env{status: 400, body: %{detail: "Validator already exists for this type and stage"}}
    end)

    {:ok, query_data} =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{"name" => "PII guard", "type" => "pii_remover", "stage" => "input"}
        }
      )

    assert [%{"message" => "Validator already exists for this type and stage"}] =
             get_in(query_data, [:data, "createGuardrailConfig", "errors"])
  end

  test "createGuardrailConfig rejects a config that is not a JSON object", %{manager: user} do
    {:ok, query_data} =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "name" => "PII guard",
            "type" => "pii_remover",
            "stage" => "input",
            "config" => Jason.encode!(["severity"])
          }
        }
      )

    assert [%{"message" => "config must be a JSON object"}] =
             get_in(query_data, [:data, "createGuardrailConfig", "errors"])
  end

  test "updateGuardrailConfig sends only the given base fields", %{manager: user} do
    Tesla.Mock.mock(fn %{method: :patch, url: url, body: body} ->
      assert String.ends_with?(url, "#{@configs_path}/#{@config_id}")
      assert Jason.decode!(body) == %{"is_enabled" => false}

      %Tesla.Env{status: 200, body: %{success: true, data: %{@kaapi_config | is_enabled: false}}}
    end)

    {:ok, query_data} =
      auth_query_gql_by(:update, user,
        variables: %{"id" => @config_id, "input" => %{"isEnabled" => false}}
      )

    assert %{"isEnabled" => false} =
             get_in(query_data, [:data, "updateGuardrailConfig", "guardrailConfig"])
  end

  test "deleteGuardrailConfig deletes the config in Kaapi", %{manager: user} do
    Tesla.Mock.mock(fn %{method: :delete, url: url} ->
      assert String.ends_with?(url, "#{@configs_path}/#{@config_id}")

      %Tesla.Env{
        status: 200,
        body: %{success: true, data: %{message: "Validator deleted successfully"}}
      }
    end)

    {:ok, query_data} = auth_query_gql_by(:delete, user, variables: %{"id" => @config_id})

    assert %{"id" => @config_id} =
             get_in(query_data, [:data, "deleteGuardrailConfig", "guardrailConfig"])
  end

  test "staff cannot create a guardrail config", %{staff: user} do
    {:ok, query_data} =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{"name" => "PII guard", "type" => "pii_remover", "stage" => "input"}
        }
      )

    assert [%{message: "Unauthorized"}] = query_data.errors
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
