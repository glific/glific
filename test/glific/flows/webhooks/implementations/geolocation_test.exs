defmodule Glific.Flows.Webhooks.Implementations.GeolocationTest do
  use Glific.DataCase, async: true

  alias Glific.Flows.Webhooks.Geolocation
  alias Glific.Flows.Webhooks.Geolocation.Address

  @ctx %{organization_id: 1, headers: []}

  @success_body Jason.encode!(%{
                  "status" => "OK",
                  "results" => [
                    %{
                      "formatted_address" => "Bangalore, Karnataka, India",
                      "address_components" => [
                        %{"types" => ["locality"], "long_name" => "Bangalore"},
                        %{
                          "types" => ["administrative_area_level_1"],
                          "long_name" => "Karnataka"
                        },
                        %{"types" => ["country"], "long_name" => "India"},
                        %{"types" => ["postal_code"], "long_name" => "560001"},
                        %{
                          "types" => ["administrative_area_level_3"],
                          "long_name" => "Bangalore Urban"
                        }
                      ]
                    }
                  ]
                })

  describe "client/0" do
    test "includes Telemetry middleware with provider metadata" do
      client = Geolocation.client()
      middleware = Tesla.Client.middleware(client)

      assert Enum.any?(middleware, fn
               {Tesla.Middleware.Telemetry, _opts} -> true
               _ -> false
             end)
    end

    test "includes retry middleware" do
      client = Geolocation.client()
      middleware = Tesla.Client.middleware(client)

      assert Enum.any?(middleware, fn
               {Tesla.Middleware.Retry, _} -> true
               _ -> false
             end)
    end

    test "does not include Logger middleware (API key in URL)" do
      client = Geolocation.client()
      middleware = Tesla.Client.middleware(client)

      refute Enum.any?(middleware, fn
               {Tesla.Middleware.Logger, _} -> true
               Tesla.Middleware.Logger -> true
               _ -> false
             end)
    end

    test "Telemetry metadata contains provider key" do
      client = Geolocation.client()
      middleware = Tesla.Client.middleware(client)

      {Tesla.Middleware.Telemetry, opts} =
        Enum.find(middleware, fn
          {Tesla.Middleware.Telemetry, _} -> true
          _ -> false
        end)

      meta = Keyword.get(opts, :metadata, %{})
      assert meta.provider == "google_maps_geocoding"
    end
  end

  describe "call/2 - success path" do
    test "returns {:ok, Address} with all components present" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: @success_body}
      end)

      assert {:ok, %Address{} = addr} =
               Geolocation.call(%{"lat" => "12.9716", "long" => "77.5946"}, @ctx)

      assert addr.city == "Bangalore"
      assert addr.state == "Karnataka"
      assert addr.country == "India"
      assert addr.postal_code == "560001"
      assert addr.district == "Bangalore Urban"
      assert addr.address == "Bangalore, Karnataka, India"
    end

    test "component falls back to N/A when type is missing" do
      body =
        Jason.encode!(%{
          "status" => "OK",
          "results" => [
            %{
              "formatted_address" => "Somewhere",
              "address_components" => [
                %{"types" => ["country"], "long_name" => "India"}
              ]
            }
          ]
        })

      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: body}
      end)

      assert {:ok, %Address{} = addr} =
               Geolocation.call(%{"lat" => "12.9716", "long" => "77.5946"}, @ctx)

      assert addr.city == "N/A"
      assert addr.state == "N/A"
      assert addr.country == "India"
    end

    test "parses explicit status OK response" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: @success_body}
      end)

      assert {:ok, %Address{}} =
               Geolocation.call(%{"lat" => "12.9716", "long" => "77.5946"}, @ctx)
    end

    test "parses response without status field when results present" do
      body =
        Jason.encode!(%{
          "results" => [
            %{
              "formatted_address" => "Test City",
              "address_components" => [
                %{"types" => ["locality"], "long_name" => "Test City"}
              ]
            }
          ]
        })

      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: body}
      end)

      assert {:ok, %Address{city: "Test City"}} =
               Geolocation.call(%{"lat" => "10.0", "long" => "80.0"}, @ctx)
    end
  end

  describe "call/2 - transport failures" do
    test "returns unreadable-response error when body is not valid JSON" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 500, body: "Internal Server Error"}
      end)

      assert {:error, msg} = Geolocation.call(%{"lat" => "12.9716", "long" => "77.5946"}, @ctx)
      assert msg =~ "unreadable response"
    end

    test "returns {:error, string} on network failure" do
      Tesla.Mock.mock(fn %{method: :get} ->
        {:error, :timeout}
      end)

      assert {:error, msg} = Geolocation.call(%{"lat" => "12.9716", "long" => "77.5946"}, @ctx)
      assert is_binary(msg)
      assert msg =~ "timeout"
    end

    test "includes inspect output for non-string reason" do
      Tesla.Mock.mock(fn %{method: :get} ->
        {:error, %Tesla.Error{reason: :econnrefused}}
      end)

      assert {:error, msg} = Geolocation.call(%{"lat" => "12.9716", "long" => "77.5946"}, @ctx)
      assert is_binary(msg)
    end
  end

  describe "call/2 - Google Maps status codes" do
    test "ZERO_RESULTS returns descriptive error" do
      body = Jason.encode!(%{"status" => "ZERO_RESULTS", "results" => []})

      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: body}
      end)

      assert {:error, msg} = Geolocation.call(%{"lat" => "0.0", "long" => "0.0"}, @ctx)
      assert msg =~ "No address found"
    end

    test "REQUEST_DENIED with error_message includes it" do
      body =
        Jason.encode!(%{
          "status" => "REQUEST_DENIED",
          "error_message" => "This API project is not authorized"
        })

      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: body}
      end)

      assert {:error, msg} = Geolocation.call(%{"lat" => "12.9", "long" => "77.5"}, @ctx)
      assert msg =~ "Geocoding request was denied."
      assert msg =~ "This API project is not authorized"
    end

    test "REQUEST_DENIED without error_message has fallback" do
      body = Jason.encode!(%{"status" => "REQUEST_DENIED"})

      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: body}
      end)

      assert {:error, msg} = Geolocation.call(%{"lat" => "12.9", "long" => "77.5"}, @ctx)
      assert msg =~ "Geocoding request was denied."
      refute msg =~ "nil"
    end

    test "OVER_QUERY_LIMIT returns quota error" do
      body = Jason.encode!(%{"status" => "OVER_QUERY_LIMIT"})

      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: body}
      end)

      assert {:error, msg} = Geolocation.call(%{"lat" => "12.9", "long" => "77.5"}, @ctx)
      assert msg =~ "quota"
    end

    test "INVALID_REQUEST returns validation error" do
      body = Jason.encode!(%{"status" => "INVALID_REQUEST"})

      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: body}
      end)

      assert {:error, msg} = Geolocation.call(%{"lat" => "bad", "long" => "bad"}, @ctx)
      assert msg =~ "Invalid"
    end

    test "UNKNOWN_ERROR returns retry suggestion" do
      body = Jason.encode!(%{"status" => "UNKNOWN_ERROR"})

      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: body}
      end)

      assert {:error, msg} = Geolocation.call(%{"lat" => "12.9", "long" => "77.5"}, @ctx)
      assert msg =~ "unexpected error"
    end

    test "unknown status returns generic error with status code" do
      body = Jason.encode!(%{"status" => "SOME_FUTURE_STATUS"})

      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: body}
      end)

      assert {:error, msg} = Geolocation.call(%{"lat" => "12.9", "long" => "77.5"}, @ctx)
      assert msg =~ "SOME_FUTURE_STATUS"
    end

    test "empty results list without status returns error" do
      body = Jason.encode!(%{"results" => []})

      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: body}
      end)

      assert {:error, _msg} = Geolocation.call(%{"lat" => "12.9", "long" => "77.5"}, @ctx)
    end
  end

  describe "call/2 - bad response body" do
    test "returns error on invalid JSON" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: "not json at all {{"}
      end)

      assert {:error, msg} = Geolocation.call(%{"lat" => "12.9716", "long" => "77.5946"}, @ctx)
      assert is_binary(msg)
    end

    test "returns error on unexpected response structure" do
      body = Jason.encode!(%{"something_unexpected" => true})

      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: body}
      end)

      assert {:error, _msg} = Geolocation.call(%{"lat" => "12.9716", "long" => "77.5946"}, @ctx)
    end
  end

  describe "call/2 - missing / whitespace coordinates" do
    test "missing lat returns error" do
      assert {:error, "Missing lat or long field"} =
               Geolocation.call(%{"long" => "77.5946"}, @ctx)
    end

    test "missing long returns error" do
      assert {:error, "Missing lat or long field"} =
               Geolocation.call(%{"lat" => "12.9716"}, @ctx)
    end

    test "whitespace-only lat treated as missing" do
      assert {:error, "Missing lat or long field"} =
               Geolocation.call(%{"lat" => "   ", "long" => "77.5946"}, @ctx)
    end

    test "whitespace-only long treated as missing" do
      assert {:error, "Missing lat or long field"} =
               Geolocation.call(%{"lat" => "12.9716", "long" => "  "}, @ctx)
    end

    test "nil lat treated as missing" do
      assert {:error, "Missing lat or long field"} =
               Geolocation.call(%{"lat" => nil, "long" => "77.5946"}, @ctx)
    end

    test "nil long treated as missing" do
      assert {:error, "Missing lat or long field"} =
               Geolocation.call(%{"lat" => "12.9716", "long" => nil}, @ctx)
    end

    test "empty string lat treated as missing" do
      assert {:error, "Missing lat or long field"} =
               Geolocation.call(%{"lat" => "", "long" => "77.5946"}, @ctx)
    end
  end

  describe "call/2 - retry behaviour" do
    test "retries on 503 and succeeds on second attempt" do
      attempt = :counters.new(1, [])

      Tesla.Mock.mock(fn %{method: :get} ->
        count = :counters.get(attempt, 1)
        :counters.add(attempt, 1, 1)

        if count == 0 do
          %Tesla.Env{status: 503, body: "Service Unavailable"}
        else
          %Tesla.Env{status: 200, body: @success_body}
        end
      end)

      assert {:ok, %Address{}} =
               Geolocation.call(%{"lat" => "12.9716", "long" => "77.5946"}, @ctx)
    end
  end
end
