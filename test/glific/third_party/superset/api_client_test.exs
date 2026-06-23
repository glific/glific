defmodule Glific.ThirdParty.Superset.ApiClientTest do
  use Glific.DataCase
  import Tesla.Mock

  # Note: tests run synchronously (no async: true) because mock_global/1 mutates global state.

  alias Glific.ThirdParty.Superset.ApiClient

  # Note: this URL must match SUPERSET_URL in the test environment (typically from config/.env.dev)
  @base_url "https://moonshine.projecttech4dev.org/api/v1"

  describe "get_embed_token/1" do
    test "returns {:ok, %{token: _}} when all three HTTP legs succeed",
         %{organization_id: organization_id} do
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

      assert {:ok, %{token: "embed_token_xyz"}} = ApiClient.get_embed_token(organization_id)
    end

    test "returns {:error, %{status: 401, body: _}} when login returns 401",
         %{organization_id: organization_id} do
      mock_global(fn
        %{method: :post, url: url} when url == @base_url <> "/security/login" ->
          %Tesla.Env{
            status: 401,
            body: %{message: "Unauthorized"},
            headers: []
          }
      end)

      assert {:error, %{status: 401, body: _}} = ApiClient.get_embed_token(organization_id)
    end

    test "returns {:error, %{status: 500, body: _}} when CSRF token fetch returns 500",
         %{organization_id: organization_id} do
      mock_global(fn
        %{method: :post, url: url} when url == @base_url <> "/security/login" ->
          %Tesla.Env{
            status: 200,
            body: %{access_token: "test_token"},
            headers: []
          }

        %{method: :get, url: url} when url == @base_url <> "/security/csrf_token/" ->
          %Tesla.Env{
            status: 500,
            body: %{message: "Internal Server Error"},
            headers: []
          }
      end)

      assert {:error, %{status: 500, body: _}} = ApiClient.get_embed_token(organization_id)
    end

    test "propagates transport error when network is unreachable",
         %{organization_id: organization_id} do
      mock_global(fn
        %{method: :post, url: url} when url == @base_url <> "/security/login" ->
          {:error, :econnrefused}
      end)

      assert {:error, :econnrefused} = ApiClient.get_embed_token(organization_id)
    end
  end
end
