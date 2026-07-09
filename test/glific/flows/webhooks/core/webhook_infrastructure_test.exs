defmodule Glific.Flows.Webhooks.Core.WebhookInfrastructureTest do
  use Glific.DataCase, async: false

  import Mock

  alias Glific.Flows.Webhooks.{
    Dispatcher,
    Errors,
    Instrumentation,
    Registry
  }

  # --- Stub webhook modules ---------------------------------------------------

  defmodule StubWebhook do
    use Glific.Flows.Webhooks.Sync, name: "stub_infra"
    @impl true
    def call(%{"mode" => "failure"} = _fields, _ctx),
      do: %{success: false, reason: "test failure"}

    def call(%{"mode" => "raise"} = _fields, _ctx), do: raise(RuntimeError, "stub error")
    def call(%{"mode" => "string_error"} = _fields, _ctx), do: "some error string"
    def call(_fields, _ctx), do: %{success: true, value: "ok"}
  end

  defmodule StubAsyncWebhook do
    use Glific.Flows.Webhooks.Async, name: "stub_async_infra"
    @impl true
    def call(_fields, _ctx), do: %{success: true}
  end

  defmodule StubAsyncCustomWait do
    use Glific.Flows.Webhooks.Async, name: "stub_async_custom"
    @impl true
    def call(_fields, _ctx), do: %{success: true}
    @impl true
    def wait_time_default, do: 120
  end

  # --- Registry ---------------------------------------------------------------

  describe "Registry" do
    test "lookup/1 with known name returns module" do
      assert Registry.lookup("geolocation") == Glific.Flows.Webhooks.Geolocation
    end

    test "lookup/1 with unknown name returns nil" do
      assert Registry.lookup("nonexistent_webhook") == nil
    end

    test "lookup!/1 with known name returns module" do
      assert Registry.lookup!("geolocation") == Glific.Flows.Webhooks.Geolocation
    end

    test "lookup!/1 with unknown name raises ArgumentError" do
      assert_raise ArgumentError, fn ->
        Registry.lookup!("nonexistent_webhook")
      end
    end

    test "names/0 returns list containing geolocation" do
      names = Registry.names()
      assert is_list(names)
      assert "geolocation" in names
    end
  end

  # --- Instrumentation.around/3 -----------------------------------------------

  describe "Instrumentation.around/3" do
    test "passes through success result unchanged" do
      result =
        with_mocks([
          {Appsignal, [:passthrough],
           [
             send_error: fn _ex, _stack, _conf -> :ok end,
             add_distribution_value: fn _name, _val, _tags -> :ok end
           ]},
          {Appsignal.Span, [:passthrough], [set_sample_data: fn span, _k, _v -> span end]}
        ]) do
          Instrumentation.around(StubWebhook, %{organization_id: 1}, fn ->
            %{success: true, city: "Bangalore"}
          end)
        end

      assert result == %{success: true, city: "Bangalore"}
    end

    test "re-raises exceptions after reporting" do
      with_mocks([
        {Appsignal, [:passthrough],
         [
           send_error: fn _ex, _stack, configurator ->
             configurator.(:fake_span)
             :ok
           end,
           add_distribution_value: fn _name, _val, _tags -> :ok end
         ]},
        {Appsignal.Span, [:passthrough], [set_sample_data: fn span, _k, _v -> span end]}
      ]) do
        assert_raise RuntimeError, "test exception", fn ->
          Instrumentation.around(StubWebhook, %{organization_id: 1}, fn ->
            raise RuntimeError, "test exception"
          end)
        end
      end
    end

    test "reports to AppSignal when result is %{success: false}" do
      {exception, _tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, %{organization_id: 1}, fn ->
            %{success: false, reason: "API error"}
          end)
        end)

      assert %Errors.SystemError{} = exception
      assert exception.message =~ "stub_infra"
    end

    test "does not report to AppSignal when result is %{success: true}" do
      with_mocks([
        {Appsignal, [:passthrough],
         [
           send_error: fn _ex, _stack, _conf ->
             flunk("send_error should not be called for success")
           end,
           add_distribution_value: fn _name, _val, _tags -> :ok end
         ]},
        {Appsignal.Span, [:passthrough], [set_sample_data: fn span, _k, _v -> span end]}
      ]) do
        Instrumentation.around(StubWebhook, %{organization_id: 1}, fn ->
          %{success: true, city: "Test"}
        end)
      end
    end

    test "reports to AppSignal on exception" do
      {exception, _tags} =
        capture_appsignal(fn ->
          assert_raise RuntimeError, fn ->
            Instrumentation.around(StubWebhook, %{organization_id: 1}, fn ->
              raise RuntimeError, "webhook blew up"
            end)
          end
        end)

      assert %Errors.SystemError{} = exception
    end

    test "tags include organization_id from ctx" do
      {_exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, %{organization_id: 42}, fn ->
            %{success: false, reason: "oops"}
          end)
        end)

      assert tags.organization_id == 42
    end

    test "tags include webhook_name" do
      {_exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, %{organization_id: 1}, fn ->
            %{success: false}
          end)
        end)

      assert tags.webhook_name == "stub_infra"
    end
  end

  # --- Instrumentation.around/3 (async webhooks) ------------------------------
  # Async webhooks defer latency + success to callback time, so a successful ack
  # records nothing; only a dispatch failure (which never reaches the callback) is
  # recorded here.

  describe "Instrumentation.around/3 — async mode" do
    test "a successful ack records nothing (deferred to callback)" do
      result =
        with_mocks([
          {Appsignal, [:passthrough],
           [
             send_error: fn _ex, _stack, _conf -> flunk("should not report on async ack") end,
             add_distribution_value: fn _name, _val, _tags ->
               flunk("should not emit latency on async ack")
             end
           ]},
          {Appsignal.Span, [:passthrough], [set_sample_data: fn span, _k, _v -> span end]}
        ]) do
          Instrumentation.around(StubAsyncWebhook, %{organization_id: 1}, fn ->
            %{success: true}
          end)
        end

      assert result == %{success: true}
    end

    test "a dispatch failure reports SystemError" do
      {exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubAsyncWebhook, %{organization_id: 7}, fn ->
            %{success: false, reason: "boom"}
          end)
        end)

      assert %Errors.SystemError{} = exception
      assert exception.message =~ "stub_async_infra"
      assert tags.organization_id == 7
    end

    test "an exception reports SystemError and reraises" do
      {exception, _tags} =
        capture_appsignal(fn ->
          assert_raise RuntimeError, "async boom", fn ->
            Instrumentation.around(StubAsyncWebhook, %{organization_id: 1}, fn ->
              raise RuntimeError, "async boom"
            end)
          end
        end)

      assert %Errors.SystemError{} = exception
    end
  end

  # --- Dispatcher.dispatch/3 --------------------------------------------

  describe "Dispatcher.dispatch/3" do
    test "raises ArgumentError for unknown webhook name" do
      assert_raise ArgumentError, fn ->
        Dispatcher.dispatch("totally_unknown_webhook_xyz", %{})
      end
    end

    test "successful geolocation call returns success map" do
      body =
        Jason.encode!(%{
          "status" => "OK",
          "results" => [
            %{
              "formatted_address" => "Bangalore, India",
              "address_components" => [
                %{"types" => ["locality"], "long_name" => "Bangalore"},
                %{"types" => ["country"], "long_name" => "India"}
              ]
            }
          ]
        })

      with_mocks([
        {Appsignal, [:passthrough],
         [
           send_error: fn _ex, _stack, _conf -> :ok end,
           add_distribution_value: fn _name, _val, _tags -> :ok end
         ]},
        {Appsignal.Span, [:passthrough], [set_sample_data: fn span, _k, _v -> span end]}
      ]) do
        Tesla.Mock.mock(fn %{method: :get} ->
          %Tesla.Env{status: 200, body: body}
        end)

        result =
          Dispatcher.dispatch("geolocation", %{
            "lat" => "12.9716",
            "long" => "77.5946",
            "organization_id" => 1
          })

        assert is_map(result)
        assert result.success == true
        assert result.city == "Bangalore"
      end
    end

    test "geolocation failure returns error string" do
      with_mocks([
        {Appsignal, [:passthrough],
         [
           send_error: fn _ex, _stack, configurator ->
             configurator.(:fake_span)
             :ok
           end,
           add_distribution_value: fn _name, _val, _tags -> :ok end
         ]},
        {Appsignal.Span, [:passthrough], [set_sample_data: fn span, _k, _v -> span end]}
      ]) do
        Tesla.Mock.mock(fn %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(%{"status" => "ZERO_RESULTS", "results" => []})
          }
        end)

        result =
          Dispatcher.dispatch("geolocation", %{
            "lat" => "0.0",
            "long" => "0.0",
            "organization_id" => 1
          })

        assert is_binary(result)
      end
    end

    test "integer organization_id passes through in ctx" do
      with_mocks([
        {Appsignal, [:passthrough],
         [
           send_error: fn _ex, _stack, _conf -> :ok end,
           add_distribution_value: fn _name, _val, _tags -> :ok end
         ]},
        {Appsignal.Span, [:passthrough], [set_sample_data: fn span, _k, _v -> span end]},
        {Registry, [:passthrough],
         [
           lookup!: fn _name ->
             StubWebhook
           end
         ]}
      ]) do
        Dispatcher.dispatch("stub_infra", %{"organization_id" => 1})
      end
    end

    test "binary organization_id is parsed to integer" do
      with_mocks([
        {Appsignal, [:passthrough],
         [
           send_error: fn _ex, _stack, _conf -> :ok end,
           add_distribution_value: fn _name, _val, _tags -> :ok end
         ]},
        {Appsignal.Span, [:passthrough], [set_sample_data: fn span, _k, _v -> span end]},
        {Registry, [:passthrough], [lookup!: fn _name -> StubWebhook end]}
      ]) do
        Dispatcher.dispatch("stub_infra", %{"organization_id" => "42"})
      end
    end

    test "nil organization_id results in nil in ctx" do
      with_mocks([
        {Appsignal, [:passthrough],
         [
           send_error: fn _ex, _stack, _conf -> :ok end,
           add_distribution_value: fn _name, _val, _tags -> :ok end
         ]},
        {Appsignal.Span, [:passthrough], [set_sample_data: fn span, _k, _v -> span end]},
        {Registry, [:passthrough], [lookup!: fn _name -> StubWebhook end]}
      ]) do
        Dispatcher.dispatch("stub_infra", %{})
      end
    end

    test "non-numeric binary organization_id results in nil in ctx" do
      with_mocks([
        {Appsignal, [:passthrough],
         [
           send_error: fn _ex, _stack, _conf -> :ok end,
           add_distribution_value: fn _name, _val, _tags -> :ok end
         ]},
        {Appsignal.Span, [:passthrough], [set_sample_data: fn span, _k, _v -> span end]},
        {Registry, [:passthrough], [lookup!: fn _name -> StubWebhook end]}
      ]) do
        Dispatcher.dispatch("stub_infra", %{"organization_id" => "not_a_number"})
      end
    end
  end

  # --- Instrumentation.report_callback_failure/2 ------------------------------

  describe "Instrumentation.report_callback_failure/2" do
    test "reports SystemError to AppSignal when success is false" do
      response = %{
        "organization_id" => 1,
        "webhook_name" => "kaapi_asr",
        "flow_id" => 100,
        "contact_id" => 200,
        "webhook_log_id" => 300
      }

      result = %{"success" => false, "reason" => "ASR failed"}

      {exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.report_callback_failure(result, response)
        end)

      assert %Errors.SystemError{} = exception
      assert exception.message == "Webhook system_error from kaapi_asr"
      assert tags.organization_id == 1
      assert tags.webhook_name == "kaapi_asr"
      assert tags.reason == "ASR failed"
      assert tags.error_type == "system"
    end

    test "is a no-op when success is true" do
      with_mocks([
        {Appsignal, [:passthrough],
         [
           send_error: fn _ex, _stack, _conf ->
             flunk("send_error should not be called when success is true")
           end
         ]}
      ]) do
        result = %{"success" => true}
        response = %{"webhook_name" => "kaapi_asr"}
        assert :ok = Instrumentation.report_callback_failure(result, response)
      end
    end

    test "uses error key when reason is absent" do
      response = %{"organization_id" => 1, "webhook_name" => "kaapi_asr"}
      result = %{"success" => false, "error" => "error from error key"}

      {_exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.report_callback_failure(result, response)
        end)

      assert tags.reason == "error from error key"
    end

    test "falls back to default message when no reason keys present" do
      response = %{"organization_id" => 1, "webhook_name" => "kaapi_asr"}
      result = %{"success" => false}

      {_exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.report_callback_failure(result, response)
        end)

      assert tags.reason =~ "Kaapi callback failure"
    end
  end

  # --- Instrumentation.report_timeout/1 ---------------------------------------

  describe "Instrumentation.report_timeout/1" do
    test "reports TimeoutError with webhook_name in message" do
      {exception, _tags} =
        capture_appsignal(fn ->
          Instrumentation.report_timeout(%{webhook_name: "kaapi_asr", organization_id: 1})
        end)

      assert %Errors.TimeoutError{} = exception
      assert exception.message =~ "kaapi_asr"
    end

    test "falls back to 'unknown' when webhook_name absent" do
      {exception, _tags} =
        capture_appsignal(fn ->
          Instrumentation.report_timeout(%{organization_id: 1})
        end)

      assert %Errors.TimeoutError{} = exception
      assert exception.message =~ "unknown"
    end

    test "tags include organization_id" do
      {_exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.report_timeout(%{webhook_name: "kaapi_asr", organization_id: 99})
        end)

      assert tags.organization_id == 99
    end
  end

  # --- Sync / Async macro behaviour -------------------------------------------

  describe "Sync macro" do
    test "name/0 returns the registered name" do
      assert StubWebhook.name() == "stub_infra"
    end

    test "mode/0 returns :sync" do
      assert StubWebhook.mode() == :sync
    end
  end

  describe "Async macro" do
    test "name/0 returns the registered name" do
      assert StubAsyncWebhook.name() == "stub_async_infra"
    end

    test "mode/0 returns :async" do
      assert StubAsyncWebhook.mode() == :async
    end

    test "wait_time_default/0 returns 60 by default" do
      assert StubAsyncWebhook.wait_time_default() == 60
    end

    test "wait_time_default/0 is overridable" do
      assert StubAsyncCustomWait.wait_time_default() == 120
    end
  end

  # --- Errors module ----------------------------------------------------------

  describe "Errors module" do
    test "SystemError is a valid exception" do
      ex = %Errors.SystemError{message: "test"}
      assert Exception.message(ex) == "test"
    end

    test "TimeoutError is a valid exception" do
      ex = %Errors.TimeoutError{message: "timeout test"}
      assert Exception.message(ex) == "timeout test"
    end

    test "Error is a valid exception" do
      ex = %Errors.Error{message: "generic error"}
      assert Exception.message(ex) == "generic error"
    end
  end

  # End-to-end config-vs-system routing through Instrumentation → ErrorClassifier.
  describe "ErrorClassifier routing" do
    test "Kaapi-not-active dispatch failure → system (module verdict)" do
      {exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.report_failure("speech_to_text", %{
            organization_id: 1,
            reason: "Kaapi is not active"
          })
        end)

      assert %Errors.SystemError{} = exception
      assert tags.error_type == "system"
    end

    test "geolocation input error → config (module verdict)" do
      {exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.report_failure("geolocation", %{
            organization_id: 1,
            reason: "Invalid geocoding request. Invalid 'latlng' parameter."
          })
        end)

      assert %Errors.ConfigurationError{} = exception
      assert tags.error_type == "config"
    end

    test "OpenAI 400 (unresolved var) callback → config via the heuristic" do
      response = %{
        "organization_id" => 1,
        "webhook_name" => "filesearch-gpt",
        "flow_id" => 1,
        "contact_id" => 2,
        "webhook_log_id" => 3
      }

      result = %{
        "success" => false,
        "error" => "OpenAI bad request (code: 400): Invalid 'conversation.id': '@contact...'"
      }

      {exception, _tags} =
        capture_appsignal(fn -> Instrumentation.report_callback_failure(result, response) end)

      assert %Errors.ConfigurationError{} = exception
    end

    test "stale resume (no active flows) is suppressed — no incident" do
      with_mocks([
        {Appsignal, [:passthrough],
         [
           send_error: fn _ex, _st, _cf -> flunk("stale must not report an incident") end,
           increment_counter: fn _n, _v, _t -> :ok end
         ]}
      ]) do
        assert :ok =
                 Instrumentation.report_resume_failure(
                   %{"organization_id" => 1, "webhook_name" => "filesearch-gpt"},
                   "123 does not have any active flows awaiting results."
                 )
      end
    end

    test "conversation_locked callback is transient — no incident" do
      with_mocks([
        {Appsignal, [:passthrough],
         [
           send_error: fn _ex, _st, _cf -> flunk("transient must not report an incident") end,
           increment_counter: fn _n, _v, _t -> :ok end
         ]}
      ]) do
        response = %{"organization_id" => 1, "webhook_name" => "filesearch-gpt"}

        result = %{
          "success" => false,
          "error" => "OpenAI bad request (code: 400): ... 'code': 'conversation_locked' ..."
        }

        assert :ok = Instrumentation.report_callback_failure(result, response)
      end
    end
  end

  # --- Private helpers --------------------------------------------------------

  defp capture_appsignal(fun) do
    test_pid = self()

    with_mocks([
      {Appsignal, [:passthrough],
       [
         send_error: fn ex, _stack, configurator ->
           send(test_pid, {:appsignal_exception, ex})
           configurator.(:fake_span)
           :ok
         end,
         add_distribution_value: fn _name, _val, _tags -> :ok end
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
        {:appsignal_exception, ex} -> drain_appsignal_exceptions(ex)
      after
        200 -> flunk("Appsignal.send_error was not called within 200ms")
      end

    tags =
      receive do
        {:appsignal_tag, "tags", t} -> t
      after
        100 -> %{}
      end

    {exception, tags}
  end

  defp drain_appsignal_exceptions(last) do
    receive do
      {:appsignal_exception, ex} -> drain_appsignal_exceptions(ex)
    after
      0 -> last
    end
  end
end
