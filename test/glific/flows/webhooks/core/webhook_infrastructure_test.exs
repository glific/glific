defmodule Glific.Flows.Webhooks.WebhookInfrastructureTest do
  use Glific.DataCase, async: false

  alias Glific.Flows.Webhook.SystemError
  alias Glific.Flows.Webhooks.{Dispatcher, Instrumentation, Registry}

  import Mock

  # ─── Stub webhook used across all infrastructure tests ───────────────────

  defmodule StubWebhook do
    @moduledoc false
    use Glific.Flows.Webhooks.Sync, name: "stub"

    @impl true
    def call(%{"mode" => "fail"} = fields, _ctx),
      do: %{success: false, error: fields["error"] || "stub failure"}

    def call(%{"mode" => "raise"}, _ctx),
      do: raise(RuntimeError, "stub explosion")

    def call(_fields, _ctx),
      do: %{success: true, result: "ok"}
  end

  @org_id 1
  @base_fields %{"organization_id" => @org_id}
  @fail_fields Map.merge(@base_fields, %{"mode" => "fail", "error" => "intentional failure"})

  # ─── Registry ────────────────────────────────────────────────────────────

  describe "Registry" do
    test "lookup/1 returns the module for a registered webhook" do
      assert Registry.lookup("geolocation") != nil
    end

    test "lookup/1 returns nil for an unregistered webhook" do
      assert Registry.lookup("not_a_webhook") == nil
    end

    test "lookup!/1 returns the module for a registered webhook" do
      assert is_atom(Registry.lookup!("geolocation"))
    end

    test "lookup!/1 raises ArgumentError for an unregistered webhook" do
      assert_raise ArgumentError, fn -> Registry.lookup!("not_a_webhook") end
    end

    test "names/0 returns a non-empty list of binary strings" do
      names = Registry.names()
      assert is_list(names)
      assert names != []
      assert Enum.all?(names, &is_binary/1)
    end
  end

  # ─── Instrumentation.around/3 ────────────────────────────────────────────

  describe "Instrumentation.around/3" do
    test "passes the return value through on success" do
      ctx = %{organization_id: @org_id}

      with_mocks([{Glific.Metrics, [:passthrough], [increment: fn _event -> :ok end]}]) do
        result =
          Instrumentation.around(StubWebhook, ctx, fn -> %{success: true, result: "ok"} end)

        assert result == %{success: true, result: "ok"}
      end
    end

    test "failure responses report exactly one SystemError to AppSignal" do
      ctx = %{organization_id: @org_id}

      {exception, tags} =
        capture_appsignal(fn ->
          result =
            Instrumentation.around(StubWebhook, ctx, fn ->
              %{success: false, error: "intentional failure"}
            end)

          refute result[:success]
        end)

      assert %SystemError{message: "Webhook system_error from stub"} = exception
      assert tags[:webhook_name] == "stub"
      assert tags[:organization_id] == @org_id
      assert tags[:reason] == "intentional failure"
    end

    test "success responses do not report to AppSignal" do
      ctx = %{organization_id: @org_id}
      test_pid = self()

      with_mocks([
        {Appsignal, [:passthrough],
         [send_error: fn ex, _stack, _conf -> send(test_pid, {:unexpected_appsignal, ex}) end]},
        {Glific.Metrics, [:passthrough], [increment: fn _event -> :ok end]}
      ]) do
        Instrumentation.around(StubWebhook, ctx, fn -> %{success: true} end)
      end

      refute_received {:unexpected_appsignal, _}
    end

    test "rescued exceptions are reported and re-raised" do
      ctx = %{organization_id: @org_id}

      assert_raise RuntimeError, "stub explosion", fn ->
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, ctx, fn -> raise(RuntimeError, "stub explosion") end)
        end)
      end
    end

    test "emits flow_webhook_latency distribution on success" do
      ctx = %{organization_id: @org_id}
      test_pid = self()

      with_mocks([
        {Appsignal, [:passthrough],
         [
           add_distribution_value: fn name, value, tags ->
             send(test_pid, {:latency, name, value, tags})
             :ok
           end
         ]},
        {Glific.Metrics, [:passthrough], [increment: fn _event -> :ok end]}
      ]) do
        Instrumentation.around(StubWebhook, ctx, fn -> %{success: true} end)
      end

      assert_received {:latency, "flow_webhook_latency", _value, tags}
      assert tags.webhook_name == "stub"
      assert tags.mode == "sync"
      assert tags.outcome == "ok"
    end

    test "emits flow_webhook_latency distribution on failure" do
      ctx = %{organization_id: @org_id}
      test_pid = self()

      with_mocks([
        {Appsignal, [:passthrough],
         [
           add_distribution_value: fn name, value, tags ->
             send(test_pid, {:latency, name, value, tags})
             :ok
           end,
           send_error: fn _ex, _stack, _conf -> :ok end
         ]},
        {Appsignal.Span, [:passthrough], [set_sample_data: fn _span, _k, _v -> :fake_span end]},
        {Glific.Metrics, [:passthrough], [increment: fn _event -> :ok end]}
      ]) do
        Instrumentation.around(StubWebhook, ctx, fn ->
          %{success: false, error: "intentional failure"}
        end)
      end

      assert_received {:latency, "flow_webhook_latency", _value, tags}
      assert tags.webhook_name == "stub"
      assert tags.outcome == "ok"
    end

    test "increments success metric with dynamic webhook name on success" do
      ctx = %{organization_id: @org_id}
      test_pid = self()

      with_mocks([
        {Glific.Metrics, [:passthrough],
         [increment: fn event -> send(test_pid, {:metric, event}) end]},
        {Appsignal, [:passthrough], [add_distribution_value: fn _n, _v, _t -> :ok end]}
      ]) do
        Instrumentation.around(StubWebhook, ctx, fn -> %{success: true} end)
      end

      assert_received {:metric, "Stub API Success"}
    end

    test "increments failure metric with dynamic webhook name on failure" do
      ctx = %{organization_id: @org_id}
      test_pid = self()

      with_mocks([
        {Glific.Metrics, [:passthrough],
         [increment: fn event -> send(test_pid, {:metric, event}) end]},
        {Appsignal, [:passthrough],
         [
           add_distribution_value: fn _n, _v, _t -> :ok end,
           send_error: fn _ex, _stack, _conf -> :ok end
         ]},
        {Appsignal.Span, [:passthrough], [set_sample_data: fn _span, _k, _v -> :fake_span end]}
      ]) do
        Instrumentation.around(StubWebhook, ctx, fn ->
          %{success: false, error: "oops"}
        end)
      end

      assert_received {:metric, "Stub API Failure"}
    end
  end

  # ─── Dispatcher ──────────────────────────────────────────────────────────

  describe "Dispatcher.dispatch_named/3" do
    test "routes to the registered module and returns its result" do
      with_mocks([
        {Registry, [:passthrough], [lookup!: fn _name -> StubWebhook end]},
        {Glific.Metrics, [:passthrough], [increment: fn _event -> :ok end]}
      ]) do
        result = Dispatcher.dispatch_named("stub", @base_fields)
        assert result[:success] == true
        assert result[:result] == "ok"
      end
    end

    test "failure from the webhook propagates back through the dispatcher" do
      with_mocks([{Registry, [:passthrough], [lookup!: fn _name -> StubWebhook end]}]) do
        capture_appsignal(fn ->
          result = Dispatcher.dispatch_named("stub", @fail_fields)
          refute result[:success]
          assert result[:error] == "intentional failure"
        end)
      end
    end

    test "raises ArgumentError for an unregistered webhook name" do
      assert_raise ArgumentError, fn ->
        Dispatcher.dispatch_named("not_a_webhook", @base_fields)
      end
    end

    test "routes to the geolocation webhook and returns structured address data" do
      Tesla.Mock.mock(fn %{method: :get} ->
        body =
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

        %Tesla.Env{status: 200, body: body}
      end)

      with_mocks([{Glific.Metrics, [:passthrough], [increment: fn _event -> :ok end]}]) do
        result =
          Dispatcher.dispatch_named("geolocation", %{
            "lat" => "37.7749",
            "long" => "-122.4194",
            "organization_id" => @org_id
          })

        assert result[:success] == true
        assert result[:city] == "San Francisco"
        assert result[:state] == "CA"
        assert result[:country] == "USA"
        assert result[:address] == "San Francisco, CA, USA"
      end
    end
  end

  # ─── Instrumentation public reporters ────────────────────────────────────

  describe "Instrumentation.report_callback_failure/2" do
    test "builds a callback-shaped SystemError with the right tags" do
      result = %{
        "success" => false,
        "reason" => "kaapi exploded",
        "error_type" => "service_unavailable"
      }

      response = %{
        "organization_id" => @org_id,
        "webhook_name" => "stub",
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
      assert tags[:webhook_name] == "stub"
      assert tags[:flow_id] == 99
      assert tags[:contact_id] == 7
      assert tags[:webhook_log_id] == 42
      assert tags[:error_type] == "service_unavailable"
      assert tags[:reason] == "kaapi exploded"
    end

    test "is a no-op when success is true" do
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

  # ─── Helpers ─────────────────────────────────────────────────────────────

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
       ]},
      {Glific.Metrics, [:passthrough], [increment: fn _event -> :ok end]}
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
