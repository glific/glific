defmodule GlificWeb.Schema.TemplateRephraseTest do
  @moduledoc """
  GraphQL integration tests for the TemplateRephrase surface:
  - rephraseTemplateBody mutation
  - templateRephrase query (poll)
  - authorization enforcement
  - cross-org isolation
  - full async loop (mutation → callback → poll)
  """

  use GlificWeb.ConnCase
  use Wormwood.GQLCase
  import Tesla.Mock

  alias Glific.{
    Partners,
    Repo,
    TemplateRephrase,
    TemplateRephrase.TemplateRephraseRequest
  }

  load_gql(:create, GlificWeb.Schema, "assets/gql/template_rephrase/create.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/template_rephrase/by_id.gql")

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

    FunWithFlags.enable(:is_template_ai_assist_enabled, for_actor: %{organization_id: org_id})

    :ok
  end

  defp kaapi_success_mock do
    mock(fn %Tesla.Env{method: :post} ->
      %Tesla.Env{status: 200, body: %{data: %{job_id: "job_tr_test"}, success: true}}
    end)
  end

  @valid_input %{
    "text" => "Hi {{1}}, your order {{2}} has shipped!",
    "action" => "PROFESSIONAL"
  }

  # ---------------------------------------------------------------------------
  # rephraseTemplateBody mutation
  # ---------------------------------------------------------------------------

  describe "rephraseTemplateBody mutation" do
    setup :enable_kaapi

    test "staff user can rephrase a template body and receives :in_progress row",
         %{staff: user} do
      kaapi_success_mock()

      result = auth_query_gql_by(:create, user, variables: %{"input" => @valid_input})

      assert {:ok, query_data} = result

      template_rephrase =
        get_in(query_data, [:data, "rephraseTemplateBody", "templateRephrase"])

      assert template_rephrase["status"] == "in_progress"
      assert template_rephrase["id"] != nil
      assert get_in(query_data, [:data, "rephraseTemplateBody", "errors"]) in [nil, []]
    end

    test "manager user can also rephrase a template body", %{manager: user} do
      kaapi_success_mock()

      result = auth_query_gql_by(:create, user, variables: %{"input" => @valid_input})

      assert {:ok, query_data} = result

      template_rephrase =
        get_in(query_data, [:data, "rephraseTemplateBody", "templateRephrase"])

      assert template_rephrase["status"] == "in_progress"
    end

    test "is rejected when the :is_template_ai_assist_enabled flag is off for the org",
         %{staff: user, organization_id: org_id} do
      FunWithFlags.disable(:is_template_ai_assist_enabled, for_actor: %{organization_id: org_id})

      result = auth_query_gql_by(:create, user, variables: %{"input" => @valid_input})

      assert {:ok, query_data} = result
      message = get_in(query_data, [:errors, Access.at(0), :message])
      assert message =~ "not enabled"
    end

    test "user with no authorized role is rejected", %{staff: user} do
      no_role_user = %{user | roles: []}

      result = auth_query_gql_by(:create, no_role_user, variables: %{"input" => @valid_input})

      assert {:ok, query_data} = result
      errors = get_in(query_data, [:errors])
      assert errors != nil
      assert length(errors) > 0
    end

    test "text over 1024 chars is rejected", %{staff: user} do
      oversized = String.duplicate("x", 1_025)

      result =
        auth_query_gql_by(:create, user,
          variables: %{"input" => Map.put(@valid_input, "text", oversized)}
        )

      assert {:ok, query_data} = result
      errors = get_in(query_data, [:errors])
      assert errors != nil && length(errors) > 0
    end

    test "action CUSTOM with missing customPrompt is rejected", %{staff: user} do
      input = Map.put(@valid_input, "action", "CUSTOM")

      result = auth_query_gql_by(:create, user, variables: %{"input" => input})

      assert {:ok, query_data} = result
      errors = get_in(query_data, [:errors])
      assert errors != nil && length(errors) > 0
    end

    test "action CUSTOM with blank customPrompt is rejected", %{staff: user} do
      input =
        @valid_input
        |> Map.put("action", "CUSTOM")
        |> Map.put("customPrompt", "   ")

      result = auth_query_gql_by(:create, user, variables: %{"input" => input})

      assert {:ok, query_data} = result
      errors = get_in(query_data, [:errors])
      assert errors != nil && length(errors) > 0
    end

    test "action CUSTOM with a valid customPrompt succeeds", %{staff: user} do
      kaapi_success_mock()

      input =
        @valid_input
        |> Map.put("action", "CUSTOM")
        |> Map.put("customPrompt", "Make it sound urgent")

      result = auth_query_gql_by(:create, user, variables: %{"input" => input})

      assert {:ok, query_data} = result

      template_rephrase =
        get_in(query_data, [:data, "rephraseTemplateBody", "templateRephrase"])

      assert template_rephrase["status"] == "in_progress"
    end

    test "action PROFESSIONAL accepted even if a stray customPrompt is sent (ignored)",
         %{staff: user} do
      kaapi_success_mock()

      input = Map.put(@valid_input, "customPrompt", "this should be ignored")

      result = auth_query_gql_by(:create, user, variables: %{"input" => input})

      assert {:ok, query_data} = result

      template_rephrase =
        get_in(query_data, [:data, "rephraseTemplateBody", "templateRephrase"])

      assert template_rephrase["status"] == "in_progress"
    end

    test "action UTILITY accepted even if a stray customPrompt is sent (ignored)",
         %{staff: user} do
      kaapi_success_mock()

      input =
        @valid_input
        |> Map.put("action", "UTILITY")
        |> Map.put("customPrompt", "this should be ignored")

      result = auth_query_gql_by(:create, user, variables: %{"input" => input})

      assert {:ok, query_data} = result

      template_rephrase =
        get_in(query_data, [:data, "rephraseTemplateBody", "templateRephrase"])

      assert template_rephrase["status"] == "in_progress"
    end
  end

  # ---------------------------------------------------------------------------
  # templateRephrase query (poll)
  # ---------------------------------------------------------------------------

  describe "templateRephrase query" do
    setup :enable_kaapi

    test "staff user can fetch a template rephrase request by id",
         %{staff: user, organization_id: org_id} do
      {:ok, request} =
        %TemplateRephraseRequest{}
        |> TemplateRephraseRequest.changeset(%{
          original_text: "Hi {{1}}",
          action: :professional,
          status: :in_progress,
          request_id: "req_poll_001",
          organization_id: org_id
        })
        |> Repo.insert()

      result = auth_query_gql_by(:by_id, user, variables: %{"id" => request.id})

      assert {:ok, query_data} = result

      template_rephrase =
        get_in(query_data, [:data, "templateRephrase", "templateRephrase"])

      assert template_rephrase["id"] == to_string(request.id)
      assert template_rephrase["status"] == "in_progress"
    end

    test "non-existent id returns Resource not found in errors", %{staff: user} do
      result = auth_query_gql_by(:by_id, user, variables: %{"id" => 999_999_999})

      assert {:ok, query_data} = result

      message =
        get_in(query_data, [:data, "templateRephrase", "errors", Access.at(0), "message"])

      assert message == "Resource not found"
    end

    test "cross-org isolation: request from org A is not visible to org B user",
         %{staff: user, organization_id: org_id} do
      {:ok, request} =
        %TemplateRephraseRequest{}
        |> TemplateRephraseRequest.changeset(%{
          original_text: "Org A template",
          action: :professional,
          status: :in_progress,
          request_id: "req_cross_org_001",
          organization_id: org_id
        })
        |> Repo.insert()

      # Simulate a staff user belonging to a *different* org by overriding organization_id.
      # The Repo.fetch_by in the resolver scopes to user.organization_id, so org 2 cannot
      # see org 1's request — this tests the resolver's explicit org-scoping.
      other_org_user = %{user | organization_id: org_id + 1}

      result = auth_query_gql_by(:by_id, other_org_user, variables: %{"id" => request.id})

      assert {:ok, query_data} = result

      message =
        get_in(query_data, [:data, "templateRephrase", "errors", Access.at(0), "message"])

      assert message == "Resource not found"
    end
  end

  # ---------------------------------------------------------------------------
  # Full async loop: mutation → callback → poll shows :ready
  # ---------------------------------------------------------------------------

  describe "full async loop" do
    setup :enable_kaapi

    test "rephrase → callback → poll returns status :ready with rephrasedText",
         %{staff: user} do
      kaapi_success_mock()

      # Step 1: trigger rephrasing
      {:ok, mutation_data} =
        auth_query_gql_by(:create, user, variables: %{"input" => @valid_input})

      template_rephrase_id =
        get_in(mutation_data, [:data, "rephraseTemplateBody", "templateRephrase", "id"])

      assert template_rephrase_id != nil

      # Step 2: look up the created row to get its request_id (the callback correlation key)
      {:ok, request} =
        Repo.fetch(TemplateRephraseRequest, String.to_integer(template_rephrase_id),
          skip_organization_id: true
        )

      assert is_binary(request.request_id)

      # Step 3: simulate the Kaapi callback (real shape, correlated by request_id)
      {:ok, _updated} =
        TemplateRephrase.handle_callback(%{
          "success" => true,
          "data" => %{
            "response" => %{
              "output" => %{"content" => %{"value" => "Hello {{1}}, your order shipped."}}
            }
          },
          "error" => nil,
          "errors" => nil,
          "metadata" => %{"request_id" => request.request_id}
        })

      # Step 4: poll via GraphQL and assert :ready
      {:ok, poll_data} =
        auth_query_gql_by(:by_id, user,
          variables: %{"id" => String.to_integer(template_rephrase_id)}
        )

      template_rephrase = get_in(poll_data, [:data, "templateRephrase", "templateRephrase"])

      assert template_rephrase["status"] == "ready"
      assert template_rephrase["rephrasedText"] =~ "Hello"
    end
  end
end
