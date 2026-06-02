defmodule Glific.Flows.Webhooks.GeolocationTest do
  @moduledoc """
  Unit tests for `Glific.Flows.Webhooks.Geolocation.call/2`.

  All Tesla HTTP calls are mocked. Routing via Dispatcher and CommonWebhook
  is covered in `WebhookInfrastructureTest` and `CommonWebhookTest` respectively.
  """

  use Glific.DataCase, async: false

  alias Glific.Flows.Webhooks.Geolocation

  @fields %{"lat" => "37.7749", "long" => "-122.4194", "organization_id" => 1}
  @ctx %{organization_id: 1}

  @sf_response Jason.encode!(%{
                 "results" => [
                   %{
                     "address_components" => [
                       %{"long_name" => "San Francisco", "types" => ["locality"]},
                       %{"long_name" => "CA", "types" => ["administrative_area_level_1"]},
                       %{"long_name" => "USA", "types" => ["country"]},
                       %{"long_name" => "94102", "types" => ["postal_code"]},
                       %{
                         "long_name" => "San Francisco County",
                         "types" => ["administrative_area_level_3"]
                       }
                     ],
                     "formatted_address" => "San Francisco, CA, USA"
                   }
                 ]
               })

  describe "Geolocation.call/2 — success cases" do
    test "parses all address components from the Google Maps response" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: @sf_response}
      end)

      result = Geolocation.call(@fields, @ctx)

      assert result[:success] == true
      assert result[:city] == "San Francisco"
      assert result[:state] == "CA"
      assert result[:country] == "USA"
      assert result[:postal_code] == "94102"
      assert result[:district] == "San Francisco County"
      assert result[:address] == "San Francisco, CA, USA"
    end

    test "falls back to \"N/A\" for address components not present in the response" do
      Tesla.Mock.mock(fn %{method: :get} ->
        body =
          Jason.encode!(%{
            "results" => [
              %{
                "address_components" => [
                  %{"long_name" => "San Francisco", "types" => ["locality"]}
                ],
                "formatted_address" => "San Francisco"
              }
            ]
          })

        %Tesla.Env{status: 200, body: body}
      end)

      result = Geolocation.call(@fields, @ctx)

      assert result[:success] == true
      assert result[:city] == "San Francisco"
      assert result[:state] == "N/A"
      assert result[:country] == "N/A"
      assert result[:postal_code] == "N/A"
      assert result[:district] == "N/A"
    end
  end

  describe "Geolocation.call/2 — failure cases" do
    test "returns error map on non-200 HTTP status" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 500, body: "Internal Server Error"}
      end)

      result = Geolocation.call(@fields, @ctx)

      refute result[:success]
      assert result[:error] =~ "HTTP error 500"
      assert result[:error] =~ "Google Maps API key"
    end

    test "returns error map on network failure" do
      Tesla.Mock.mock(fn %{method: :get} ->
        {:error, :econnrefused}
      end)

      result = Geolocation.call(@fields, @ctx)

      refute result[:success]
      assert result[:error] =~ "Could not connect"
      assert result[:error] =~ "econnrefused"
    end

    test "returns error map when results list is empty" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: Jason.encode!(%{"results" => []})}
      end)

      result = Geolocation.call(@fields, @ctx)

      refute result[:success]
      assert result[:error] =~ "No address found"
      assert result[:error] =~ "latitude and longitude"
    end

    test "returns error map when response body is not valid JSON" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: "not json at all {{{"}
      end)

      result = Geolocation.call(@fields, @ctx)

      refute result[:success]
      assert result[:error] =~ "unreadable response"
    end

    test "returns error map when response body has unexpected JSON structure" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: Jason.encode!(%{"status" => "REQUEST_DENIED"})}
      end)

      result = Geolocation.call(@fields, @ctx)

      refute result[:success]
      assert result[:error] =~ "unexpected response format"
    end
  end

end
