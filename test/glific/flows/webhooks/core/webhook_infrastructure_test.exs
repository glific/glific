defmodule Glific.Flows.Webhooks.WebhookInfrastructureTest do
  use Glific.DataCase, async: false

  alias Glific.Flows.Webhook
  alias Glific.Flows.Webhook.SystemError
  alias Glific.Flows.Webhooks.{Dispatcher, Errors, Instrumentation, Registry}

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

  defmodule StubAsyncWebhook do
    @moduledoc false
    use Glific.Flows.Webhooks.Async, name: "stub_async"

    @impl true
    def call(_fields, _ctx), do: %{success: true}
  end

  defmodule StubAsyncCustomWait do
    @moduledoc false
    use Glific.Flows.Webhooks.Async, name: "stub_async_custom"

    @impl true
    def call(_fields, _ctx), do: %{success: true}

    @impl true
    def wait_time_default, do: 120
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

  # ─── Errors ──────────────────────────────────────────────────────────────

  describe "Errors" do
    test "system_error/0 returns the SystemError module" do
      assert Errors.system_error() == Glific.Flows.Webhook.SystemError
    end

    test "timeout_error/0 returns the TimeoutError module" do
      assert Errors.timeout_error() == Glific.Flows.Webhook.TimeoutError
    end

    test "generic_error/0 returns the Error module" do
      assert Errors.generic_error() == Glific.Flows.Webhook.Error
    end
  end

  # ─── Async macro ─────────────────────────────────────────────────────────

  describe "Async macro" do
    test "name/0 returns the configured webhook name" do
      assert StubAsyncWebhook.name() == "stub_async"
    end

    test "mode/0 returns :async" do
      assert StubAsyncWebhook.mode() == :async
    end

    test "wait_time_default/0 returns 60 by default" do
      assert StubAsyncWebhook.wait_time_default() == 60
    end

    test "wait_time_default/0 can be overridden" do
      assert StubAsyncCustomWait.wait_time_default() == 120
    end
  end

  # ─── Instrumentation.report_timeout/1 ────────────────────────────────────

  describe "Instrumentation.report_timeout/1" do
    test "reports a TimeoutError to AppSignal with the webhook name" do
      test_pid = self()
      tags = %{webhook_name: "stub", organization_id: @org_id, flow_id: 10}

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
        Instrumentation.report_timeout(tags)
      end

      assert_received {:appsignal_exception, %Webhook.TimeoutError{message: "Webhook timeout from stub"}}
    end

    test "falls back to 'unknown' when webhook_name is missing" do
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
         [set_sample_data: fn _span, _k, _v -> :fake_span end]}
      ]) do
        Instrumentation.report_timeout(%{organization_id: @org_id})
      end

      assert_received {:appsignal_exception, %Webhook.TimeoutError{message: "Webhook timeout from unknown"}}
    end
  end

  # ─── Instrumentation.around/3 — nil / non-map results ────────────────────

  describe "Instrumentation.around/3 — non-success result shapes" do
    test "nil return value is treated as a failure" do
      ctx = %{organization_id: @org_id}

      {exception, _tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, ctx, fn -> nil end)
        end)

      assert %SystemError{} = exception
    end

    test "binary string return value is treated as a failure with the string as reason" do
      ctx = %{organization_id: @org_id}

      {exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, ctx, fn -> "something went wrong" end)
        end)

      assert %SystemError{} = exception
      assert tags[:reason] == "something went wrong"
    end

    test "non-map, non-nil, non-string return is inspected as the reason" do
      ctx = %{organization_id: @org_id}

      {exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, ctx, fn -> 42 end)
        end)

      assert %SystemError{} = exception
      assert tags[:reason] == "42"
    end
  end

  # ─── extract_status_and_reason via around/3 ──────────────────────────────

  describe "extract_status_and_reason — all pattern branches (via around/3)" do
    setup do
      ctx = %{organization_id: @org_id}
      {:ok, ctx: ctx}
    end

    test "http_status + reason both present", %{ctx: ctx} do
      {_ex, tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, ctx, fn ->
            %{success: false, http_status: 503, reason: "service unavailable"}
          end)
        end)

      assert tags[:http_status] == 503
      assert tags[:reason] == "service unavailable"
    end

    test "http_status only (no reason)", %{ctx: ctx} do
      {_ex, tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, ctx, fn ->
            %{success: false, http_status: 429}
          end)
        end)

      assert tags[:http_status] == 429
    end

    test "asr_response_text as integer", %{ctx: ctx} do
      {_ex, _tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, ctx, fn ->
            %{success: false, asr_response_text: 500}
          end)
        end)
    end

    test "asr_response_text as binary", %{ctx: ctx} do
      {_ex, tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, ctx, fn ->
            %{success: false, asr_response_text: "transcription error"}
          end)
        end)

      assert tags[:reason] == "transcription error"
    end

    test "reason as binary", %{ctx: ctx} do
      {_ex, tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, ctx, fn ->
            %{success: false, reason: "bad credentials"}
          end)
        end)

      assert tags[:reason] == "bad credentials"
    end

    test "other catch-all (no recognisable keys)", %{ctx: ctx} do
      {_ex, _tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, ctx, fn ->
            %{success: false, unknown_key: "value"}
          end)
        end)
    end
  end

  # ─── Dispatcher.build_ctx — org_id coercion ──────────────────────────────

  describe "Dispatcher.dispatch_named/3 — organization_id coercion" do
    test "accepts a binary organization_id" do
      with_mocks([
        {Registry, [:passthrough], [lookup!: fn _name -> StubWebhook end]},
        {Glific.Metrics, [:passthrough], [increment: fn _event -> :ok end]}
      ]) do
        result =
          Dispatcher.dispatch_named("stub", %{"organization_id" => "1"})

        assert result[:success] == true
      end
    end

    test "handles nil organization_id without crashing" do
      with_mocks([
        {Registry, [:passthrough], [lookup!: fn _name -> StubWebhook end]},
        {Glific.Metrics, [:passthrough], [increment: fn _event -> :ok end]}
      ]) do
        result = Dispatcher.dispatch_named("stub", %{})
        assert result[:success] == true
      end
    end

    test "handles non-integer, non-binary organization_id without crashing" do
      with_mocks([
        {Registry, [:passthrough], [lookup!: fn _name -> StubWebhook end]},
        {Glific.Metrics, [:passthrough], [increment: fn _event -> :ok end]}
      ]) do
        result = Dispatcher.dispatch_named("stub", %{"organization_id" => :atom_value})
        assert result[:success] == true
      end
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
