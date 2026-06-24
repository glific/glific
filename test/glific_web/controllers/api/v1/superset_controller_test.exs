defmodule GlificWeb.API.V1.SupersetControllerTest do
  use GlificWeb.ConnCase
  import Tesla.Mock

  # Note: tests run synchronously (no async: true) because mock_global/1 mutates global state.

  alias Glific.Fixtures

  @base_url "https://moonshine.projecttech4dev.org/api/v1"

  defp mock_superset_success do
    mock_global(fn
      %{method: :post, url: url} when url == @base_url <> "/security/login" ->
        %Tesla.Env{
          status: 200,
          body: %{access_token: "test_token"},
          headers: []
        }

      %{method: :get, url: url} when url == @base_url <> "/security/csrf_token/" ->
        %Tesla.Env{
          status: 200,
          body: %{result: "csrf123"},
          headers: [{"set-cookie", "session=abc123; Path=/"}]
        }

      %{method: :post, url: url} when url == @base_url <> "/security/guest_token/" ->
        %Tesla.Env{
          status: 200,
          body: %{token: "embed_token_xyz"},
          headers: []
        }
    end)
  end

  describe "POST /api/v1/get-embed-token" do
    test "returns 200 with a token when Superset API succeeds",
         %{conn: conn, organization_id: organization_id} do
      FunWithFlags.enable(:superset_enabled, for_actor: %{organization_id: organization_id})
      mock_superset_success()
      authed_conn = api_auth_conn(conn, Fixtures.user_fixture(%{roles: ["staff"]}))
      conn = post(authed_conn, "/api/v1/get-embed-token")
      response = json_response(conn, 200)
      assert is_binary(response["token"])
      assert response["token"] != ""
    end

    test "returns 401 when no authorization header is provided", %{conn: conn} do
      conn = post(conn, "/api/v1/get-embed-token")
      response = json_response(conn, 401)
      assert response["error"]["code"] == 401
    end

    test "returns 403 when superset_enabled flag is off for the organization",
         %{conn: conn, organization_id: organization_id} do
      FunWithFlags.disable(:superset_enabled, for_actor: %{organization_id: organization_id})
      authed_conn = api_auth_conn(conn, Fixtures.user_fixture(%{roles: ["staff"]}))
      conn = post(authed_conn, "/api/v1/get-embed-token")
      response = json_response(conn, 403)
      assert response["error"]["status"] == 403
      assert response["error"]["message"] =~ "not enabled"
    end

    test "returns 503 with a generic message when Superset login fails",
         %{conn: conn, organization_id: organization_id} do
      FunWithFlags.enable(:superset_enabled, for_actor: %{organization_id: organization_id})

      mock_global(fn
        %{method: :post, url: url} when url == @base_url <> "/security/login" ->
          %Tesla.Env{
            status: 401,
            body: %{message: "Invalid credentials"},
            headers: []
          }
      end)

      authed_conn = api_auth_conn(conn, Fixtures.user_fixture(%{roles: ["staff"]}))
      conn = post(authed_conn, "/api/v1/get-embed-token")
      response = json_response(conn, 503)
      assert Map.has_key?(response, "error")
      assert response["error"]["status"] == 503

      assert response["error"]["message"] =~
               "Please retry, or contact support if the issue persists."
    end

    test "sends an empty rls list in guest token request (UI-level org filtering active)",
         %{conn: conn, organization_id: organization_id} do
      FunWithFlags.enable(:superset_enabled, for_actor: %{organization_id: organization_id})
      test_pid = self()

      mock_global(fn
        %{method: :post, url: url} when url == @base_url <> "/security/login" ->
          %Tesla.Env{status: 200, body: %{access_token: "test_token"}, headers: []}

        %{method: :get, url: url} when url == @base_url <> "/security/csrf_token/" ->
          %Tesla.Env{
            status: 200,
            body: %{result: "csrf123"},
            headers: [{"set-cookie", "session=abc123; Path=/"}]
          }

        %{method: :post, url: url, body: body}
        when url == @base_url <> "/security/guest_token/" ->
          send(test_pid, {:guest_token_body, body})
          %Tesla.Env{status: 200, body: %{token: "embed_token_xyz"}, headers: []}
      end)

      post(api_auth_conn(conn, Fixtures.user_fixture(%{roles: ["staff"]})), "/api/v1/get-embed-token")

      assert_receive {:guest_token_body, body}
      decoded = Jason.decode!(body)
      assert decoded["rls"] == []
    end
  end
end
