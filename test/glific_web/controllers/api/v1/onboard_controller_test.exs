defmodule GlificWeb.API.V1.OnboardControllerTest do
  use GlificWeb.ConnCase

  alias Glific.Seeds.SeedsDev

  @reachout_params %{
    "name" => "Jane Doe",
    "email" => "jane@example.org",
    "org_name" => "Some NGO",
    "message" => "We would like to know more about Glific."
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_users()
    %{saas_organization: organization}
  end

  defp mock_captcha(success?, score) do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://www.google.com/recaptcha/api/siteverify"} ->
        %Tesla.Env{
          status: 200,
          body: Jason.encode!(%{"success" => success?, "score" => score, "action" => "reachout"})
        }
    end)
  end

  describe "reachout/2" do
    test "sends the query when the captcha passes", %{conn: conn} do
      mock_captcha(true, 0.9)

      conn = post(conn, "/api/v1/onboard/reachout", Map.put(@reachout_params, "token", "a_token"))

      assert %{"is_valid" => true} = json_response(conn, 200)
    end

    test "rejects the query without a captcha token", %{conn: conn} do
      conn = post(conn, "/api/v1/onboard/reachout", @reachout_params)

      assert %{"error" => %{"status" => 400, "message" => "Captcha token is missing"}} =
               json_response(conn, 400)
    end

    test "rejects the query with an empty captcha token", %{conn: conn} do
      conn = post(conn, "/api/v1/onboard/reachout", Map.put(@reachout_params, "token", ""))

      assert %{"error" => %{"message" => "Captcha token is missing"}} = json_response(conn, 400)
    end

    test "rejects the query when the captcha score is too low", %{conn: conn} do
      mock_captcha(true, 0.1)

      conn = post(conn, "/api/v1/onboard/reachout", Map.put(@reachout_params, "token", "a_token"))

      assert %{"error" => %{"message" => "Failed to verify Google Captcha" <> _}} =
               json_response(conn, 400)
    end
  end

  describe "setup/2" do
    test "rejects the request without a captcha token", %{conn: conn} do
      conn = post(conn, "/api/v1/onboard/setup", %{"name" => "Some NGO"})

      assert %{"error" => %{"message" => "Captcha token is missing"}} = json_response(conn, 400)
    end
  end
end
