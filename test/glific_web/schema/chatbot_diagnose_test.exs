defmodule GlificWeb.Schema.ChatbotDiagnoseTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Flows
  }

  load_gql(:diagnose, GlificWeb.Schema, "assets/gql/chatbot_diagnose/diagnose.gql")

  test "chatbot_diagnose returns org-level data with no filters", %{staff: user} do
    result =
      auth_query_gql_by(:diagnose, user, variables: %{"input" => %{}})

    assert {:ok, query_data} = result
    data = get_in(query_data, [:data, "chatbotDiagnose"])
    assert data != nil
    assert is_list(data["notifications"])
    assert is_list(data["obanJobs"])
    assert data["diagnostics"] != nil
    assert is_integer(data["diagnostics"]["recentErrorCount"])
    assert is_integer(data["diagnostics"]["pendingObanJobs"])
  end

  test "chatbot_diagnose returns contact data when phone filter provided", %{staff: user} do
    contact = Fixtures.contact_fixture()

    result =
      auth_query_gql_by(:diagnose, user,
        variables: %{
          "input" => %{
            "contact" => %{"phone" => contact.phone}
          }
        }
      )

    assert {:ok, query_data} = result
    data = get_in(query_data, [:data, "chatbotDiagnose"])
    assert data["contactInfo"] != nil
    assert data["contactInfo"]["phone"] == contact.phone
    assert is_list(data["messages"])
    assert data["diagnostics"]["contactOptedIn"] != nil
  end

  test "chatbot_diagnose returns flow data when name filter provided", %{staff: user} do
    [flow | _] =
      Flows.list_flows(%{filter: %{organization_id: 1}, opts: %{limit: 1}})

    result =
      auth_query_gql_by(:diagnose, user,
        variables: %{
          "input" => %{
            "flow" => %{"name" => flow.name}
          }
        }
      )

    assert {:ok, query_data} = result
    data = get_in(query_data, [:data, "chatbotDiagnose"])
    assert data["flowInfo"] != nil
    assert data["flowInfo"]["name"] == flow.name
    assert is_list(data["flowRevisions"])
  end

  test "chatbot_diagnose respects include filter", %{staff: user} do
    contact = Fixtures.contact_fixture()

    result =
      auth_query_gql_by(:diagnose, user,
        variables: %{
          "input" => %{
            "contact" => %{"phone" => contact.phone},
            "include" => ["CONTACT_INFO", "NOTIFICATIONS"]
          }
        }
      )

    assert {:ok, query_data} = result
    data = get_in(query_data, [:data, "chatbotDiagnose"])
    assert data["contactInfo"] != nil
    assert is_list(data["notifications"])
  end

  test "chatbot_diagnose respects time_range and limit", %{staff: user} do
    result =
      auth_query_gql_by(:diagnose, user,
        variables: %{
          "input" => %{
            "timeRange" => "1h",
            "limit" => 5
          }
        }
      )

    assert {:ok, query_data} = result
    data = get_in(query_data, [:data, "chatbotDiagnose"])
    assert length(data["notifications"]) <= 5
  end

  test "chatbot_diagnose handles non-existent contact gracefully", %{staff: user} do
    result =
      auth_query_gql_by(:diagnose, user,
        variables: %{
          "input" => %{
            "contact" => %{"phone" => "000000000000"}
          }
        }
      )

    assert {:ok, query_data} = result
    data = get_in(query_data, [:data, "chatbotDiagnose"])
    assert data["contactInfo"] == nil
    assert data["messages"] == []
  end
end
