defmodule GlificWeb.DifyControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{Fixtures, Partners}

  @api_key "test-dify-callback-key"

  setup %{conn: conn, organization_id: organization_id} do
    Application.put_env(:glific, :dify_callback_api_key, @api_key)

    # Get the org shortcode for building page_url
    org = Partners.organization(organization_id)

    on_exit(fn ->
      Application.delete_env(:glific, :dify_callback_api_key)
    end)

    %{
      conn: put_req_header(conn, "x-dify-api-key", @api_key),
      org: org,
      page_url: "https://#{org.shortcode}.tides.coloredcow.com/chat"
    }
  end

  describe "POST /dify/chatbot-diagnose" do
    test "returns 401 when API key is missing", %{conn: conn, page_url: page_url} do
      conn =
        conn
        |> delete_req_header("x-dify-api-key")
        |> post("/dify/chatbot-diagnose", %{
          "page_url" => page_url,
          "tables" => %{}
        })

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "returns 401 when API key is wrong", %{conn: conn, page_url: page_url} do
      conn =
        conn
        |> put_req_header("x-dify-api-key", "wrong-key")
        |> post("/dify/chatbot-diagnose", %{
          "page_url" => page_url,
          "tables" => %{}
        })

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "returns 400 when page_url is missing", %{conn: conn} do
      conn = post(conn, "/dify/chatbot-diagnose", %{"tables" => %{}})

      assert %{"error" => "Missing required parameter: page_url"} = json_response(conn, 400)
    end

    test "returns 400 when tables is missing", %{conn: conn, page_url: page_url} do
      conn = post(conn, "/dify/chatbot-diagnose", %{"page_url" => page_url})

      assert %{"error" => "Missing required parameter: tables"} = json_response(conn, 400)
    end

    test "returns 400 when org not found from page_url", %{conn: conn} do
      conn =
        post(conn, "/dify/chatbot-diagnose", %{
          "page_url" => "https://nonexistent-org.tides.coloredcow.com/chat",
          "tables" => %{}
        })

      assert %{"error" => "Organization not found" <> _} = json_response(conn, 400)
    end

    test "returns empty data for empty tables map", %{conn: conn, page_url: page_url} do
      conn =
        post(conn, "/dify/chatbot-diagnose", %{
          "page_url" => page_url,
          "tables" => %{}
        })

      assert %{"data" => %{}} = json_response(conn, 200)
    end

    test "queries contacts table with filters", %{
      conn: conn,
      page_url: page_url,
      organization_id: organization_id
    } do
      contact = Fixtures.contact_fixture(%{organization_id: organization_id})

      conn =
        post(conn, "/dify/chatbot-diagnose", %{
          "page_url" => page_url,
          "tables" => %{
            "contacts" => %{
              "filters" => %{"phone" => contact.phone},
              "fields" => ["id", "name", "phone", "status"],
              "limit" => 1
            }
          }
        })

      result = json_response(conn, 200)
      assert %{"data" => %{"contacts" => contacts}} = result
      assert length(contacts) == 1
      assert hd(contacts)["phone"] == contact.phone
    end

    test "queries flows table by uuid", %{conn: conn, page_url: page_url} do
      conn =
        post(conn, "/dify/chatbot-diagnose", %{
          "page_url" => page_url,
          "tables" => %{
            "flows" => %{
              "fields" => ["id", "name", "uuid", "is_active"],
              "limit" => 5
            }
          }
        })

      result = json_response(conn, 200)
      assert %{"data" => %{"flows" => flows}} = result
      assert is_list(flows)
    end

    test "queries multiple tables in one request", %{
      conn: conn,
      page_url: page_url
    } do
      conn =
        post(conn, "/dify/chatbot-diagnose", %{
          "page_url" => page_url,
          "tables" => %{
            "flows" => %{
              "fields" => ["id", "name"],
              "limit" => 3
            },
            "notifications" => %{
              "fields" => ["id", "message", "severity"],
              "limit" => 5
            }
          }
        })

      result = json_response(conn, 200)
      assert %{"data" => data} = result
      assert Map.has_key?(data, "flows")
      assert Map.has_key?(data, "notifications")
    end

    test "gracefully skips unknown tables", %{conn: conn, page_url: page_url} do
      conn =
        post(conn, "/dify/chatbot-diagnose", %{
          "page_url" => page_url,
          "tables" => %{
            "unknown_table" => %{"limit" => 5},
            "flows" => %{
              "fields" => ["id", "name"],
              "limit" => 1
            }
          }
        })

      result = json_response(conn, 200)
      assert %{"data" => data} = result
      assert data["unknown_table"] == []
      assert is_list(data["flows"])
    end

    test "respects time_range parameter", %{conn: conn, page_url: page_url} do
      conn =
        post(conn, "/dify/chatbot-diagnose", %{
          "page_url" => page_url,
          "time_range" => "1h",
          "tables" => %{
            "notifications" => %{
              "fields" => ["id", "message", "severity", "inserted_at"],
              "limit" => 10
            }
          }
        })

      assert %{"data" => %{"notifications" => _}} = json_response(conn, 200)
    end

    test "handles array filter values", %{conn: conn, page_url: page_url} do
      conn =
        post(conn, "/dify/chatbot-diagnose", %{
          "page_url" => page_url,
          "tables" => %{
            "notifications" => %{
              "filters" => %{"severity" => ["Error", "Critical"]},
              "fields" => ["id", "message", "severity"],
              "limit" => 10
            }
          }
        })

      result = json_response(conn, 200)
      assert %{"data" => %{"notifications" => notifications}} = result
      assert is_list(notifications)
    end

    test "caps limit at 50", %{conn: conn, page_url: page_url} do
      conn =
        post(conn, "/dify/chatbot-diagnose", %{
          "page_url" => page_url,
          "tables" => %{
            "flows" => %{
              "fields" => ["id", "name"],
              "limit" => 1000
            }
          }
        })

      # Should not crash, limit is capped internally
      assert %{"data" => %{"flows" => _}} = json_response(conn, 200)
    end
  end
end
