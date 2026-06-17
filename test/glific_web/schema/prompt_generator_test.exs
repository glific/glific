defmodule GlificWeb.Schema.PromptGeneratorTest do
  @moduledoc """
  GraphQL integration tests for the PromptGenerator surface:
  - generatePrompt mutation
  - promptGeneration query (poll)
  - authorization enforcement
  - cross-org isolation
  - full async loop (mutation → callback → poll)
  """

  use GlificWeb.ConnCase
  use Wormwood.GQLCase
  import Tesla.Mock

  alias Glific.{
    Partners,
    PromptGenerator,
    PromptGenerator.PromptGenerationRequest,
    Repo
  }

  load_gql(:create, GlificWeb.Schema, "assets/gql/prompt_generator/create.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/prompt_generator/by_id.gql")

  # ---------------------------------------------------------------------------
  # Setup helpers
  # ---------------------------------------------------------------------------

  defp enable_kaapi(%{organization_id: org_id}) do
    {:ok, credential} =
      Partners.create_credential(%{
        organization_id: org_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"}
      })

    {:ok, _credential} =
      Partners.update_credential(credential, %{
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"},
        is_active: true,
        organization_id: org_id,
        shortcode: "kaapi"
      })

    :ok
  end

  defp kaapi_success_mock do
    mock(fn %Tesla.Env{method: :post} ->
      %Tesla.Env{
        status: 200,
        body: %{data: %{job_id: "job_pg_test"}, success: true}
      }
    end)
  end

  @valid_input %{
    "name" => "Pratham Education",
    "purpose" => "Help children learn",
    "audience" => "Children in rural India"
  }

  # ---------------------------------------------------------------------------
  # generatePrompt mutation
  # ---------------------------------------------------------------------------

  describe "generatePrompt mutation" do
    setup :enable_kaapi

    test "staff user can generate a prompt and receives :in_progress row",
         %{staff: user} do
      kaapi_success_mock()

      result =
        auth_query_gql_by(:create, user, variables: %{"input" => @valid_input})

      assert {:ok, query_data} = result

      prompt_generation =
        get_in(query_data, [:data, "generatePrompt", "promptGeneration"])

      assert prompt_generation["status"] == "in_progress"
      assert prompt_generation["id"] != nil
      assert get_in(query_data, [:data, "generatePrompt", "errors"]) in [nil, []]
    end

    test "manager user can also generate a prompt",
         %{manager: user} do
      kaapi_success_mock()

      result =
        auth_query_gql_by(:create, user, variables: %{"input" => @valid_input})

      assert {:ok, query_data} = result

      prompt_generation =
        get_in(query_data, [:data, "generatePrompt", "promptGeneration"])

      assert prompt_generation["status"] == "in_progress"
    end

    test "user with no authorized role is rejected",
         %{staff: user} do
      # Override the user's roles to an empty list — the Authorize middleware
      # will reject it with an Unauthorized error since no valid role is present.
      no_role_user = %{user | roles: []}

      result =
        auth_query_gql_by(:create, no_role_user, variables: %{"input" => @valid_input})

      assert {:ok, query_data} = result
      errors = get_in(query_data, [:errors])
      assert errors != nil
      assert length(errors) > 0
    end

    test "input field exceeding 2000 chars returns an error",
         %{staff: user} do
      oversized = String.duplicate("x", 2_001)

      result =
        auth_query_gql_by(:create, user,
          variables: %{"input" => Map.put(@valid_input, "name", oversized)}
        )

      assert {:ok, query_data} = result
      errors = get_in(query_data, [:errors])
      assert errors != nil && length(errors) > 0
    end
  end

  # ---------------------------------------------------------------------------
  # promptGeneration query (poll)
  # ---------------------------------------------------------------------------

  describe "promptGeneration query" do
    setup :enable_kaapi

    test "staff user can fetch a prompt generation request by id",
         %{staff: user, organization_id: org_id} do
      {:ok, request} =
        %PromptGenerationRequest{}
        |> PromptGenerationRequest.changeset(%{
          inputs: %{"name" => "Test NGO"},
          status: :in_progress,
          kaapi_job_id: "job_poll_001",
          organization_id: org_id
        })
        |> Repo.insert()

      result =
        auth_query_gql_by(:by_id, user, variables: %{"id" => request.id})

      assert {:ok, query_data} = result

      prompt_generation =
        get_in(query_data, [:data, "promptGeneration", "promptGeneration"])

      assert prompt_generation["id"] == to_string(request.id)
      assert prompt_generation["status"] == "in_progress"
    end

    test "non-existent id returns Resource not found in errors",
         %{staff: user} do
      result =
        auth_query_gql_by(:by_id, user, variables: %{"id" => 999_999_999})

      assert {:ok, query_data} = result

      message =
        get_in(query_data, [:data, "promptGeneration", "errors", Access.at(0), "message"])

      assert message == "Resource not found"
    end

    test "cross-org isolation: request from org A is not visible to org B user",
         %{staff: user, organization_id: org_id} do
      # Create a request in org 1 (the default test org)
      {:ok, request} =
        %PromptGenerationRequest{}
        |> PromptGenerationRequest.changeset(%{
          inputs: %{"name" => "Org A NGO"},
          status: :in_progress,
          kaapi_job_id: "job_cross_org_001",
          organization_id: org_id
        })
        |> Repo.insert()

      # Simulate a staff user belonging to a *different* org by overriding organization_id.
      # The Repo.fetch_by in the resolver scopes to user.organization_id, so org 2 cannot
      # see org 1's request — this tests the resolver's explicit org-scoping.
      other_org_user = %{user | organization_id: org_id + 1}

      result =
        auth_query_gql_by(:by_id, other_org_user, variables: %{"id" => request.id})

      assert {:ok, query_data} = result

      message =
        get_in(query_data, [:data, "promptGeneration", "errors", Access.at(0), "message"])

      assert message == "Resource not found"
    end
  end

  # ---------------------------------------------------------------------------
  # Full async loop: mutation → callback → poll shows :ready
  # ---------------------------------------------------------------------------

  describe "full async loop" do
    setup :enable_kaapi

    test "generate → callback → poll returns status :ready with generated_prompt",
         %{staff: user, organization_id: org_id} do
      kaapi_success_mock()

      # Step 1: trigger generation
      {:ok, mutation_data} =
        auth_query_gql_by(:create, user, variables: %{"input" => @valid_input})

      prompt_id =
        get_in(mutation_data, [:data, "generatePrompt", "promptGeneration", "id"])

      assert prompt_id != nil

      # Step 2: look up the created row to get the kaapi_job_id
      {:ok, request} =
        Repo.fetch(PromptGenerationRequest, String.to_integer(prompt_id),
          skip_organization_id: true
        )

      assert request.kaapi_job_id == "job_pg_test"

      # Step 3: simulate the Kaapi callback
      {:ok, _updated} =
        PromptGenerator.handle_callback(%{
          "data" => %{
            "job_id" => request.kaapi_job_id,
            "status" => "SUCCESSFUL",
            "text" => "You are a helpful chatbot for #{org_id}.",
            "error_message" => nil
          }
        })

      # Step 4: poll via GraphQL and assert :ready
      {:ok, poll_data} =
        auth_query_gql_by(:by_id, user, variables: %{"id" => String.to_integer(prompt_id)})

      pg = get_in(poll_data, [:data, "promptGeneration", "promptGeneration"])

      assert pg["status"] == "ready"
      assert pg["generatedPrompt"] =~ "helpful chatbot"
    end
  end
end
