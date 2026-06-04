defmodule Glific.Flows.Webhooks.GeolocationTest do
  @moduledoc """
  Unit tests for `Glific.Flows.Webhooks.Geolocation.call/2`.

  `call/2` returns raw `{:ok, Address.t()}` / `{:error, String.t()}` tuples.
  Wire-format encoding (map vs failure string) is applied in the dispatcher and
  covered in `WebhookInfrastructureTest` and `CommonWebhookTest`.
  """

  use Glific.DataCase, async: true

  alias Glific.Flows.Webhooks.Geolocation
  alias Glific.Flows.Webhooks.Geolocation.Address

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

  describe "client/0 middleware" do
    test "includes Retry and Telemetry middleware but not Logger (API key protection)" do
      middleware = Geolocation.client() |> Tesla.Client.middleware()

      middleware_modules =
        Enum.map(middleware, fn
          {mod, _opts} -> mod
          mod -> mod
        end)

      refute Tesla.Middleware.Logger in middleware_modules
      assert Tesla.Middleware.Retry in middleware_modules
      assert Tesla.Middleware.Telemetry in middleware_modules

      {Tesla.Middleware.Telemetry, telemetry_opts} =
        Enum.find(middleware, fn
          {Tesla.Middleware.Telemetry, _} -> true
          _ -> false
        end)

      assert telemetry_opts[:metadata][:provider] == "google_maps_geocoding"
    end
  end

  describe "retry behavior" do
    test "retries on HTTP 503 and eventually succeeds" do
      {:ok, call_count} = Agent.start_link(fn -> 0 end)

      Tesla.Mock.mock(fn %{method: :get} ->
        count = Agent.get_and_update(call_count, fn n -> {n, n + 1} end)

        if count == 0 do
          %Tesla.Env{status: 503, body: "Service Unavailable"}
        else
          %Tesla.Env{status: 200, body: @sf_response}
        end
      end)

      assert {:ok, %Address{city: "San Francisco"}} = Geolocation.call(@fields, @ctx)
      assert Agent.get(call_count, & &1) == 2
    end

    test "retries on :timeout and eventually succeeds" do
      {:ok, call_count} = Agent.start_link(fn -> 0 end)

      Tesla.Mock.mock(fn %{method: :get} ->
        count = Agent.get_and_update(call_count, fn n -> {n, n + 1} end)

        if count == 0 do
          {:error, :timeout}
        else
          %Tesla.Env{status: 200, body: @sf_response}
        end
      end)

      assert {:ok, %Address{}} = Geolocation.call(@fields, @ctx)
      assert Agent.get(call_count, & &1) == 2
    end
  end

  describe "Geolocation.call/2 — success cases" do
    test "returns {:ok, Address} with parsed fields" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: @sf_response}
      end)

      assert {:ok, address} = Geolocation.call(@fields, @ctx)

      assert %Address{
               city: "San Francisco",
               state: "CA",
               country: "USA",
               postal_code: "94102",
               district: "San Francisco County",
               address: "San Francisco, CA, USA"
             } = address
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

      assert {:ok, %Address{} = address} = Geolocation.call(@fields, @ctx)
      assert address.city == "San Francisco"
      assert address.state == "N/A"
      assert address.country == "N/A"
      assert address.postal_code == "N/A"
      assert address.district == "N/A"
    end
  end

  describe "Geolocation.call/2 — failure cases" do
    test "returns {:error, message} on non-200 HTTP status" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 500, body: "Internal Server Error"}
      end)

      assert {:error, message} = Geolocation.call(@fields, @ctx)
      assert message =~ "HTTP error 500"
      assert message =~ "Internal Server Error"
      assert message =~ "Google Maps API key"
    end

    test "returns {:error, message} on network failure" do
      Tesla.Mock.mock(fn %{method: :get} ->
        {:error, :econnrefused}
      end)

      assert {:error, message} = Geolocation.call(@fields, @ctx)
      assert message =~ "Could not connect"
      assert message =~ "econnrefused"
    end

    test "returns {:error, message} when status is ZERO_RESULTS" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: Jason.encode!(%{"status" => "ZERO_RESULTS", "results" => []})
        }
      end)

      assert {:error, message} = Geolocation.call(@fields, @ctx)
      assert message =~ "No address found"
      assert message =~ "latitude and longitude"
    end

    test "returns {:error, message} when results list is empty without status" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: Jason.encode!(%{"results" => []})}
      end)

      assert {:error, message} = Geolocation.call(@fields, @ctx)
      assert message =~ "No address found"
      assert message =~ "latitude and longitude"
    end

    test "returns {:error, message} when status is REQUEST_DENIED with error_message" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "status" => "REQUEST_DENIED",
              "results" => [],
              "error_message" => "This API project is not authorized to use this API."
            })
        }
      end)

      assert {:error, message} = Geolocation.call(@fields, @ctx)
      assert message =~ "Geocoding request was denied"
      assert message =~ "This API project is not authorized to use this API"
      assert message =~ "Google Maps API key"
    end

    test "returns {:error, message} when status is OVER_QUERY_LIMIT" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "status" => "OVER_QUERY_LIMIT",
              "results" => [],
              "error_message" => "You have exceeded your daily request quota for this API."
            })
        }
      end)

      assert {:error, message} = Geolocation.call(@fields, @ctx)
      assert message =~ "Geocoding quota exceeded"
      assert message =~ "You have exceeded your daily request quota"
    end

    test "returns {:error, message} when status is INVALID_REQUEST" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "status" => "INVALID_REQUEST",
              "results" => [],
              "error_message" => "Invalid request. Missing the 'latlng' parameter."
            })
        }
      end)

      assert {:error, message} = Geolocation.call(@fields, @ctx)
      assert message =~ "Invalid geocoding request"
      assert message =~ "Missing the 'latlng' parameter"
    end

    test "returns {:error, message} when status is UNKNOWN_ERROR" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: Jason.encode!(%{"status" => "UNKNOWN_ERROR", "results" => []})
        }
      end)

      assert {:error, message} = Geolocation.call(@fields, @ctx)
      assert message =~ "unexpected error"
    end

    test "returns {:error, message} with status code for unrecognised status strings" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "status" => "NOT_FOUND",
              "results" => [],
              "error_message" => "Custom error detail."
            })
        }
      end)

      assert {:error, message} = Geolocation.call(@fields, @ctx)
      assert message =~ "NOT_FOUND"
      assert message =~ "Custom error detail"
    end

    test "returns {:error, message} when response body is not valid JSON" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: "not json at all {{{"}
      end)

      assert {:error, message} = Geolocation.call(@fields, @ctx)
      assert message =~ "unreadable response"
    end

    test "returns {:error, message} when response body has unexpected JSON structure" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: Jason.encode!(%{"status" => "REQUEST_DENIED"})}
      end)

      assert {:error, message} = Geolocation.call(@fields, @ctx)
      assert message =~ "Geocoding request was denied"
      assert message =~ "Google Maps API key"
    end

    test "returns {:error, message} when response body lacks status and results" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: Jason.encode!(%{"plus_code" => %{}})}
      end)

      assert {:error, message} = Geolocation.call(@fields, @ctx)
      assert message =~ "unexpected response format"
    end

    test "returns {:error, message} when lat or long is missing" do
      assert {:error, "Missing lat or long field"} =
               Geolocation.call(%{"lat" => "", "long" => "-122.4194"}, @ctx)
    end

    test "returns {:error, message} when lat or long is whitespace-only" do
      assert {:error, "Missing lat or long field"} =
               Geolocation.call(%{"lat" => "   ", "long" => "-122.4194"}, @ctx)
    end

    test "returns {:error, message} when response body is valid JSON but not a map" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: Jason.encode!(["not", "a", "map"])}
      end)

      assert {:error, message} = Geolocation.call(@fields, @ctx)
      assert message =~ "unexpected response format"
    end
  end

  describe "Geolocation.call/2 — status OK path" do
    test "returns {:ok, Address} when response includes status OK and results" do
      Tesla.Mock.mock(fn %{method: :get} ->
        body =
          Jason.encode!(%{
            "status" => "OK",
            "results" => [
              %{
                "address_components" => [
                  %{"long_name" => "Mumbai", "types" => ["locality"]},
                  %{"long_name" => "Maharashtra", "types" => ["administrative_area_level_1"]},
                  %{"long_name" => "India", "types" => ["country"]},
                  %{"long_name" => "400001", "types" => ["postal_code"]},
                  %{"long_name" => "Mumbai Suburban", "types" => ["administrative_area_level_3"]}
                ],
                "formatted_address" => "Mumbai, Maharashtra, India"
              }
            ]
          })

        %Tesla.Env{status: 200, body: body}
      end)

      assert {:ok, %Address{city: "Mumbai", state: "Maharashtra", country: "India"}} =
               Geolocation.call(@fields, @ctx)
    end
  end
end
