defmodule Glific.Flows.Webhooks.GeolocationTest do
  use Glific.DataCase, async: false

  alias Glific.Clients.CommonWebhook
  alias Glific.Flows.Webhook.SystemError
  alias Glific.Flows.Webhooks.{Dispatcher, Geolocation, Instrumentation, Registry}

  import Mock

  @fields %{"lat" => "37.7749", "long" => "-122.4194", "organization_id" => 1}

  describe "Registry" do
    test "geolocation is registered" do
      assert Registry.lookup("geolocation") == Geolocation
      assert Registry.lookup!("geolocation") == Geolocation
      assert "geolocation" in Registry.names()
    end

    test "lookup! raises for unregistered names" do
      assert_raise ArgumentError, fn -> Registry.lookup!("not_a_webhook") end
    end
  end

  describe "Geolocation module" do
    test "implements the Behaviour contract" do
      assert Geolocation.name() == "geolocation"
      assert Geolocation.mode() == :sync
      assert function_exported?(Geolocation, :call, 2)
    end
  end

  describe "Dispatcher routing for geolocation" do
    test "success response preserves the legacy return shape" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "results" => [
                %{
                  "address_components" => [
                    %{"long_name" => "San Francisco", "types" => ["locality"]},
                    %{"long_name" => "CA", "types" => ["administrative_area_level_1"]},
                    %{"long_name" => "USA", "types" => ["country"]}
                  ],
                  "formatted_address" => "San Francisco, CA, USA"
                }
              ]
            })
        }
      end)

      result = Dispatcher.dispatch_named("geolocation", @fields)

      assert result[:success] == true
      assert result[:city] == "San Francisco"
      assert result[:state] == "CA"
      assert result[:country] == "USA"
      assert result[:postal_code] == "N/A"
      assert result[:district] == "N/A"
      assert result[:address] == "San Francisco, CA, USA"
    end

    test "CommonWebhook.webhook(\"geolocation\", ...) routes through the dispatcher" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 500, body: "Internal Server Error"}
      end)

      result = CommonWebhook.webhook("geolocation", @fields)

      refute result[:success]
      assert result[:error] == "Received status code 500"
    end
  end

  describe "Instrumentation around the dispatcher" do
    test "failure responses report exactly one SystemError to AppSignal" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 500, body: "Internal Server Error"}
      end)

      {exception, tags} =
        capture_appsignal(fn ->
          result = Dispatcher.dispatch_named("geolocation", @fields)
          refute result[:success]
        end)

      assert %SystemError{message: "Webhook system_error from geolocation"} = exception
      assert tags[:webhook_name] == "geolocation"
      assert tags[:organization_id] == 1
      assert tags[:reason] == "Received status code 500"
    end

    test "success responses do not report to AppSignal" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "results" => [
                %{
                  "address_components" => [
                    %{"long_name" => "Boston", "types" => ["locality"]}
                  ],
                  "formatted_address" => "Boston, MA, USA"
                }
              ]
            })
        }
      end)

      test_pid = self()

      with_mocks([
        {Appsignal, [:passthrough],
         [send_error: fn ex, _stack, _conf -> send(test_pid, {:unexpected_appsignal, ex}) end]}
      ]) do
        Dispatcher.dispatch_named("geolocation", @fields)
      end

      refute_received {:unexpected_appsignal, _}
    end

    test "rescued exceptions are reported and re-raised" do
      Tesla.Mock.mock(fn %{method: :get} ->
        # Return a 200 with body that fails Jason.decode! to trigger an exception.
        %Tesla.Env{status: 200, body: "not-json"}
      end)

      assert_raise Jason.DecodeError, fn ->
        capture_appsignal(fn -> Dispatcher.dispatch_named("geolocation", @fields) end)
      end
    end
  end

  describe "Instrumentation latency telemetry" do
    test "emits flow_webhook_latency distribution on the centralised dispatcher path" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "results" => [
                %{
                  "address_components" => [
                    %{"long_name" => "Boston", "types" => ["locality"]}
                  ],
                  "formatted_address" => "Boston, MA, USA"
                }
              ]
            })
        }
      end)

      test_pid = self()

      with_mocks([
        {Appsignal, [:passthrough],
         [
           add_distribution_value: fn name, value, tags ->
             send(test_pid, {:latency, name, value, tags})
             :ok
           end
         ]}
      ]) do
        Dispatcher.dispatch_named("geolocation", @fields)
      end

      assert_received {:latency, "flow_webhook_latency", _value, tags}
      assert tags.webhook_name == "geolocation"
      assert tags.mode == "sync"
      assert tags.outcome == "ok"
    end
  end

  describe "Instrumentation public callback/timeout reporters" do
    test "report_callback_failure builds a callback-shaped SystemError with the right tags" do
      result = %{"success" => false, "reason" => "kaapi exploded", "error_type" => "service_unavailable"}

      response = %{
        "organization_id" => 1,
        "webhook_name" => "geolocation",
        "flow_id" => 99,
        "contact_id" => 7,
        "webhook_log_id" => 42,
        "message" => "ignored when reason is set"
      }

      {exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.report_callback_failure(result, response)
        end)

      assert %SystemError{message: "Webhook callback failure"} = exception
      assert tags[:webhook_name] == "geolocation"
      assert tags[:flow_id] == 99
      assert tags[:contact_id] == 7
      assert tags[:webhook_log_id] == 42
      assert tags[:error_type] == "service_unavailable"
      assert tags[:reason] == "kaapi exploded"
    end

    test "report_callback_failure is a no-op on success=true" do
      test_pid = self()

      with_mocks([
        {Appsignal, [:passthrough],
         [send_error: fn ex, _stack, _conf -> send(test_pid, {:unexpected_appsignal, ex}) end]}
      ]) do
        Instrumentation.report_callback_failure(%{"success" => true}, %{})
      end

      refute_received {:unexpected_appsignal, _}
    end
  end

  # Mirrors the helper at test/glific/flows/common_webhook_test.exs:1382 — kept
  # local for now; will move to test/support/webhook_contract_helpers.ex when
  # the contract test lands (Step 1 of the plan).
  defp capture_appsignal(fun) do
    test_pid = self()

    with_mocks([
      {Appsignal, [:passthrough],
       [
         send_error: fn ex, _stack, configurator ->
           send(test_pid, {:appsignal_exception, ex})
           configurator.(:fake_span)
           :ok
         end
       ]},
      {Appsignal.Span, [:passthrough],
       [
         set_sample_data: fn _span, key, value ->
           send(test_pid, {:appsignal_tag, key, value})
           :fake_span
         end
       ]}
    ]) do
      fun.()
    end

    exception =
      receive do
        {:appsignal_exception, ex} -> ex
      after
        100 -> flunk("Appsignal.send_error was not called")
      end

    tags =
      receive do
        {:appsignal_tag, "tags", t} -> t
      after
        100 -> %{}
      end

    {exception, tags}
  end
end
