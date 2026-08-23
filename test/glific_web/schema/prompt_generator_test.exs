defmodule GlificWeb.Schema.PromptGeneratorTest do
  @moduledoc """
  GraphQL integration tests for the PromptGenerator surface:
  - generatePrompt mutation (now resolves synchronously, via the AI runtime)
  - promptGeneration query (poll)
  - authorization enforcement
  - cross-org isolation
  - the legacy `handle_callback/1` path, still reachable via `PromptGenerator` directly

  `Glific.AI.Model.Stub` is a globally-named Agent shared across test files, so this module
  relies on `GlificWeb.ConnCase`'s default `async: false` — same reasoning as
  `test/glific/templates/utility_rewriter_test.exs`.
  """

  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    AI.Model.Stub,
    PromptGenerator,
    PromptGenerator.PromptGenerationRequest,
    Repo
  }

  load_gql(:create, GlificWeb.Schema, "assets/gql/prompt_generator/create.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/prompt_generator/by_id.gql")

  # ---------------------------------------------------------------------------
  # Setup helpers
  # ---------------------------------------------------------------------------

  defp enable_prompt_generator(%{organization_id: org_id}) do
    start_supervised!(Stub)
    FunWithFlags.enable(:is_prompt_generator_enabled, for_actor: %{organization_id: org_id})
    :ok
  end

  defp queue_generated_prompt(text) do
    Stub.queue_text("draft")
    Stub.queue_object(%{"generated_prompt" => text})
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
    setup :enable_prompt_generator

    test "staff user can generate a prompt and receives a :ready row",
         %{staff: user} do
      queue_generated_prompt("You are a helpful WhatsApp chatbot for Pratham Education.")

      result =
        auth_query_gql_by(:create, user, variables: %{"input" => @valid_input})

      assert {:ok, query_data} = result

      prompt_generation =
        get_in(query_data, [:data, "generatePrompt", "promptGeneration"])

      assert prompt_generation["status"] == "ready"

      assert prompt_generation["generatedPrompt"] ==
               "You are a helpful WhatsApp chatbot for Pratham Education."

      assert prompt_generation["id"] != nil
      assert get_in(query_data, [:data, "generatePrompt", "errors"]) in [nil, []]
    end

    test "manager user can also generate a prompt",
         %{manager: user} do
      queue_generated_prompt("You are a helpful WhatsApp chatbot.")

      result =
        auth_query_gql_by(:create, user, variables: %{"input" => @valid_input})

      assert {:ok, query_data} = result

      prompt_generation =
        get_in(query_data, [:data, "generatePrompt", "promptGeneration"])

      assert prompt_generation["status"] == "ready"
    end

    test "is rejected when the :is_prompt_generator_enabled flag is off for the org",
         %{staff: user, organization_id: org_id} do
      FunWithFlags.disable(:is_prompt_generator_enabled, for_actor: %{organization_id: org_id})

      result =
        auth_query_gql_by(:create, user, variables: %{"input" => @valid_input})

      assert {:ok, query_data} = result
      message = get_in(query_data, [:errors, Access.at(0), :message])
      assert message =~ "not enabled"
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

    test "a model-call failure still returns a :failed row, not a mutation error",
         %{staff: user} do
      Stub.queue_error(:timeout)

      result =
        auth_query_gql_by(:create, user, variables: %{"input" => @valid_input})

      assert {:ok, query_data} = result

      prompt_generation =
        get_in(query_data, [:data, "generatePrompt", "promptGeneration"])

      assert prompt_generation["status"] == "failed"
      assert get_in(query_data, [:data, "generatePrompt", "errors"]) in [nil, []]
    end
  end

  # ---------------------------------------------------------------------------
  # promptGeneration query (poll)
  # ---------------------------------------------------------------------------

  describe "promptGeneration query" do
    setup :enable_prompt_generator

    test "staff user can fetch a prompt generation request by id",
         %{staff: user, organization_id: org_id} do
      {:ok, request} =
        %PromptGenerationRequest{}
        |> PromptGenerationRequest.changeset(%{
          inputs: %{"name" => "Test NGO"},
          status: :in_progress,
          request_id: "req_poll_001",
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
          request_id: "req_cross_org_001",
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
  # Legacy callback path — GlificWeb.KaapiController.prompt_generation_callback/2 still routes
  # to PromptGenerator.handle_callback/1 (see Glific.PromptGenerator's moduledoc), even though
  # generatePrompt no longer dispatches anything to Kaapi that could ever call it back. This
  # exercises that the row it resolves is still visible through the ordinary poll query.
  # ---------------------------------------------------------------------------

  describe "legacy handle_callback/1, polled afterwards" do
    setup :enable_prompt_generator

    test "a callback-resolved row polls as :ready with generatedPrompt",
         %{staff: user, organization_id: org_id} do
      {:ok, request} =
        %PromptGenerationRequest{}
        |> PromptGenerationRequest.changeset(%{
          inputs: %{"name" => "Test NGO"},
          status: :in_progress,
          request_id: "req_legacy_001",
          organization_id: org_id
        })
        |> Repo.insert()

      {:ok, _updated} =
        PromptGenerator.handle_callback(%{
          "success" => true,
          "data" => %{
            "response" => %{
              "output" => %{"content" => %{"value" => "You are a helpful chatbot for #{org_id}."}}
            }
          },
          "error" => nil,
          "errors" => nil,
          "metadata" => %{"request_id" => request.request_id}
        })

      {:ok, poll_data} =
        auth_query_gql_by(:by_id, user, variables: %{"id" => request.id})

      pg = get_in(poll_data, [:data, "promptGeneration", "promptGeneration"])

      assert pg["status"] == "ready"
      assert pg["generatedPrompt"] =~ "helpful chatbot"
    end
  end
end
