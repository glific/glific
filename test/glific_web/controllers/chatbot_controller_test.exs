defmodule GlificWeb.ChatbotControllerTest do
  use GlificWeb.ConnCase

  @api_key "test-dify-callback-key"

  setup %{conn: conn, organization_id: organization_id} do
    # Set the API key for tests
    Application.put_env(:glific, :dify_api_key, @api_key)

    # Get the org shortcode
    org = Glific.Partners.get_organization!(organization_id)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-dify-api-key", @api_key)

    on_exit(fn ->
      Application.put_env(:glific, :dify_api_key, "This is not a secret")
    end)

    %{conn: conn, org: org, organization_id: organization_id}
  end

  describe "POST /dify/chatbot-diagnose" do
    test "returns data for a valid request", %{conn: conn, org: org} do
      params = %{
        "page_url" => "https://#{org.shortcode}.glific.com/some/path",
        "tables" => %{
          "notifications" => %{
            "fields" => ["id", "message", "severity", "inserted_at"],
            "limit" => 5
          }
        }
      }

      conn = post(conn, "/dify/chatbot-diagnose", params)
      response = json_response(conn, 200)

      assert Map.has_key?(response, "data")
      assert Map.has_key?(response["data"], "notifications")
      assert is_list(response["data"]["notifications"])
    end

    test "returns 400 when page_url is missing", %{conn: conn} do
      params = %{
        "tables" => %{
          "notifications" => %{"fields" => ["id"], "limit" => 5}
        }
      }

      conn = post(conn, "/dify/chatbot-diagnose", params)
      assert json_response(conn, 400)["error"] == "page_url is required"
    end

    test "returns 401 when API key is missing", %{conn: conn, org: org} do
      conn =
        conn
        |> delete_req_header("x-dify-api-key")

      params = %{
        "page_url" => "https://#{org.shortcode}.glific.com/path",
        "tables" => %{"notifications" => %{"fields" => ["id"], "limit" => 5}}
      }

      conn = post(conn, "/dify/chatbot-diagnose", params)
      assert json_response(conn, 401)["error"] == "Invalid or missing API key"
    end

    test "returns 401 when API key is wrong", %{conn: conn, org: org} do
      conn =
        conn
        |> put_req_header("x-dify-api-key", "wrong-key")

      params = %{
        "page_url" => "https://#{org.shortcode}.glific.com/path",
        "tables" => %{"notifications" => %{"fields" => ["id"], "limit" => 5}}
      }

      conn = post(conn, "/dify/chatbot-diagnose", params)
      assert json_response(conn, 401)["error"] == "Invalid or missing API key"
    end

    test "returns 404 when org shortcode is invalid", %{conn: conn} do
      params = %{
        "page_url" => "https://nonexistent-org.glific.com/path",
        "tables" => %{"notifications" => %{"fields" => ["id"], "limit" => 5}}
      }

      conn = post(conn, "/dify/chatbot-diagnose", params)
      assert json_response(conn, 404)["error"] == "Organization not found"
    end

    test "returns 400 when tables is missing", %{conn: conn, org: org} do
      params = %{
        "page_url" => "https://#{org.shortcode}.glific.com/path"
      }

      conn = post(conn, "/dify/chatbot-diagnose", params)
      assert json_response(conn, 400)["error"] == "tables parameter is required"
    end

    test "unknown tables are skipped gracefully", %{conn: conn, org: org} do
      params = %{
        "page_url" => "https://#{org.shortcode}.glific.com/path",
        "tables" => %{
          "nonexistent_table" => %{"fields" => ["id"], "limit" => 5},
          "notifications" => %{"fields" => ["id", "message"], "limit" => 5}
        }
      }

      conn = post(conn, "/dify/chatbot-diagnose", params)
      response = json_response(conn, 200)

      assert response["data"]["nonexistent_table"] == []
      assert is_list(response["data"]["notifications"])
    end

    test "limit is capped at 50", %{conn: conn, org: org} do
      params = %{
        "page_url" => "https://#{org.shortcode}.glific.com/path",
        "tables" => %{
          "notifications" => %{"fields" => ["id"], "limit" => 100}
        }
      }

      conn = post(conn, "/dify/chatbot-diagnose", params)
      response = json_response(conn, 200)

      # Should not error even with limit > 50
      assert is_list(response["data"]["notifications"])
    end

    test "organization scoping works - can't see other org's data",
         %{conn: conn, organization_id: organization_id} do
      params = %{
        "page_url" => "https://glific.glific.com/path",
        "tables" => %{
          "contacts" => %{
            "fields" => ["id", "name", "phone", "organization_id"],
            "limit" => 50
          }
        }
      }

      conn = post(conn, "/dify/chatbot-diagnose", params)
      response = json_response(conn, 200)

      # All returned contacts should belong to org 1
      Enum.each(response["data"]["contacts"], fn contact ->
        assert contact["organization_id"] == organization_id
      end)
    end

    test "virtual filter flow_uuid resolves correctly", %{conn: conn, org: org} do
      [flow | _] = Glific.Flows.list_flows(%{filter: %{organization_id: org.id}})

      params = %{
        "page_url" => "https://#{org.shortcode}.glific.com/path",
        "tables" => %{
          "flow_contexts" => %{
            "filters" => %{"flow_uuid" => flow.uuid},
            "fields" => ["id", "flow_id", "status", "inserted_at"],
            "limit" => 10
          }
        }
      }

      conn = post(conn, "/dify/chatbot-diagnose", params)
      response = json_response(conn, 200)

      assert is_list(response["data"]["flow_contexts"])

      # All returned flow_contexts should have the correct flow_id
      Enum.each(response["data"]["flow_contexts"], fn ctx ->
        assert ctx["flow_id"] == flow.id
      end)
    end

    test "time_range filtering works with apply_time_range flag", %{conn: conn, org: org} do
      params = %{
        "page_url" => "https://#{org.shortcode}.glific.com/path",
        "tables" => %{
          "notifications" => %{
            "fields" => ["id", "inserted_at"],
            "limit" => 10,
            "apply_time_range" => true
          }
        },
        "time_range" => "1h"
      }

      conn = post(conn, "/dify/chatbot-diagnose", params)
      response = json_response(conn, 200)

      assert is_list(response["data"]["notifications"])
    end

    test "time_range is ignored without apply_time_range flag", %{conn: conn, org: org} do
      # Even with time_range in the body, tables without apply_time_range get no filter
      params = %{
        "page_url" => "https://#{org.shortcode}.glific.com/path",
        "tables" => %{
          "contacts" => %{
            "fields" => ["id", "name"],
            "limit" => 10
          }
        },
        "time_range" => "1h"
      }

      conn = post(conn, "/dify/chatbot-diagnose", params)
      response = json_response(conn, 200)

      assert is_list(response["data"]["contacts"])
    end

    test "order parameter works", %{conn: conn, org: org} do
      params = %{
        "page_url" => "https://#{org.shortcode}.glific.com/path",
        "tables" => %{
          "contacts" => %{
            "fields" => ["id", "name", "inserted_at"],
            "limit" => 10,
            "order" => "inserted_at DESC"
          }
        }
      }

      conn = post(conn, "/dify/chatbot-diagnose", params)
      response = json_response(conn, 200)

      assert is_list(response["data"]["contacts"])
    end

    test "null filter value works", %{conn: conn, org: org} do
      params = %{
        "page_url" => "https://#{org.shortcode}.glific.com/path",
        "tables" => %{
          "flow_contexts" => %{
            "filters" => %{"completed_at" => nil},
            "fields" => ["id", "status", "completed_at"],
            "limit" => 10
          }
        }
      }

      conn = post(conn, "/dify/chatbot-diagnose", params)
      response = json_response(conn, 200)

      assert is_list(response["data"]["flow_contexts"])

      Enum.each(response["data"]["flow_contexts"], fn ctx ->
        assert is_nil(ctx["completed_at"])
      end)
    end

    test "array filter value works", %{conn: conn, org: org} do
      params = %{
        "page_url" => "https://#{org.shortcode}.glific.com/path",
        "tables" => %{
          "notifications" => %{
            "filters" => %{"severity" => ["error", "critical"]},
            "fields" => ["id", "severity"],
            "limit" => 10
          }
        }
      }

      conn = post(conn, "/dify/chatbot-diagnose", params)
      response = json_response(conn, 200)

      assert is_list(response["data"]["notifications"])
    end
  end

  describe "extract_shortcode/1" do
    test "extracts shortcode from standard URL" do
      assert {:ok, "ilp"} =
               GlificWeb.ChatbotController.extract_shortcode(
                 "https://ilp.tides.coloredcow.com/flow/configure/abc"
               )
    end

    test "extracts shortcode from simple URL" do
      assert {:ok, "myorg"} =
               GlificWeb.ChatbotController.extract_shortcode("https://myorg.glific.com/path")
    end

    test "returns error for invalid URL" do
      assert {:error, :invalid_page_url} =
               GlificWeb.ChatbotController.extract_shortcode("not-a-url")
    end

    test "returns error for URL with empty subdomain" do
      assert {:error, :invalid_page_url} =
               GlificWeb.ChatbotController.extract_shortcode("https://.glific.com/path")
    end
  end

  describe "POST /dify/chatbot-diagnose with invalid page_url" do
    test "returns 400 for URL with unparseable host", %{conn: conn} do
      params = %{
        "page_url" => "https://.glific.com/path",
        "tables" => %{"contacts" => %{"fields" => ["id"], "limit" => 5}}
      }

      conn = post(conn, "/dify/chatbot-diagnose", params)

      assert json_response(conn, 400)["error"] ==
               "Could not parse shortcode from page_url"
    end
  end
end
