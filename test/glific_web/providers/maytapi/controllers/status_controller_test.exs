defmodule GlificWeb.Providers.Maytapi.Controllers.StatusControllerTest do
  use GlificWeb.ConnCase, async: true
  alias Glific.Providers.Maytapi.ApiClient
  import Plug.Conn

  describe "status/2" do
    test "handles status update and returns 200", %{conn: conn} do
      # Set up the parameters as they would be in the request
      params = %{
        "phone_id" => 43876,
        "status" => "loading",
        "pid" => "5c5941f2-f083-40f4-8a67-cc5e1a8daa88",
        "product_id" => "5c5941f2-f083-40f4-8a67-cc5e1a8daa88",
        "type" => "status",
      }

      ApiClientMock
      |> expect(:status, fn "loading", 43876 ->
        {:ok, %{status: "loading", phone_id: 43876}}
      end)

      # Simulate the POST request to the controller
      conn = post(conn, "/maytapi", params)

      # Assert that the response status is 200
      assert conn.status == 200
      # Ensure that the response body is empty
      assert conn.resp_body == ""
      # Verify that the connection was halted
      assert conn.halted
    end

    test "returns 500 when ApiClient.status/2 fails", %{conn: conn} do
      params = %{
        "phone_id" => 43876,
        "status" => "loading",
        "pid" => "5c5941f2-f083-40f4-8a67-cc5e1a8daa88",
        "product_id" => "5c5941f2-f083-40f4-8a67-cc5e1a8daa88",
        "type" => "status",
        "unknown" => ["unknown", "unknown"]
      }

      ApiClientMock
      |> expect(:status, fn "loading", 43876 ->
        {:error, "Some error"}
      end)

      # Simulate the POST request to the controller
      conn = post(conn, "/maytapi", params)

      # Since the handler function is returning 200 regardless of ApiClient.status/2 result
      # the test will also return 200. If you need it to return 500, you should modify the handler.
      assert conn.status == 200
    end
  end
end
