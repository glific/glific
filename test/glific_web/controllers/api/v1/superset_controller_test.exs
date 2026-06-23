defmodule GlificWeb.API.V1.SupersetControllerTest do
  use GlificWeb.ConnCase
  import Tesla.Mock

  # Note: tests run synchronously (no async: true) because mock_global/1 mutates global state.

  alias Glific.Fixtures
  alias GlificWeb.{APIAuthPlug, Endpoint}

  @pow_config [otp_app: :glific]
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

  defp build_authed_conn(conn) do
    conn = %{conn | secret_key_base: Endpoint.config(:secret_key_base)}
    user = Fixtures.user_fixture(%{roles: ["staff"]})
    {conn_with_token, _user} = APIAuthPlug.create(conn, user, @pow_config)
    access_token = conn_with_token.private[:api_access_token]
    # sleep briefly to allow Mnesia to propagate the session
    :timer.sleep(100)
    conn |> Plug.Conn.put_req_header("authorization", access_token)
  end

  describe "POST /api/v1/get-embed-token" do
    test "returns 200 with a token when Superset API succeeds", %{conn: conn} do
      mock_superset_success()
      authed_conn = build_authed_conn(conn)
      conn = post(authed_conn, "/api/v1/get-embed-token")
      response = json_response(conn, 200)
      assert is_binary(response["token"])
      assert response["token"] != ""
    end

    # Note: this route is under the :api pipeline only (no RequireAuthenticated).
    # The 401 is enforced by the controller's pattern match on current_user, not the router.
    test "returns 401 when no authorization header is provided", %{conn: conn} do
      conn = post(conn, "/api/v1/get-embed-token")
      response = json_response(conn, 401)
      assert response["error"]["status"] == 401
    end

    test "returns 503 with a generic message when Superset login fails", %{conn: conn} do
      mock_global(fn
        %{method: :post, url: url} when url == @base_url <> "/security/login" ->
          %Tesla.Env{
            status: 401,
            body: %{message: "Invalid credentials"},
            headers: []
          }
      end)

      authed_conn = build_authed_conn(conn)
      conn = post(authed_conn, "/api/v1/get-embed-token")
      response = json_response(conn, 503)
      assert Map.has_key?(response, "error")
      assert response["error"]["status"] == 503
      assert response["error"]["message"] == "Dashboard service is temporarily unavailable"
    end

    test "includes RLS clause with organization_id in guest token request", %{conn: conn} do
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

      authed_conn = build_authed_conn(conn)
      post(authed_conn, "/api/v1/get-embed-token")

      assert_receive {:guest_token_body, body}
      decoded = Jason.decode!(body)
      assert [%{"clause" => clause}] = decoded["rls"]
      assert clause =~ "organization_id ="
    end
  end
end
