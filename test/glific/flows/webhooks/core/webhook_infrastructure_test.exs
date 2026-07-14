defmodule Glific.Flows.Webhooks.Core.WebhookInfrastructureTest do
  use Glific.DataCase, async: false

  import Mock

  alias Glific.Flows.Webhooks.{
    Dispatcher,
    Errors,
    Instrumentation,
    Registry
  }

  alias Glific.Messages

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

    test "reports to AppSignal on exception (tagged error_type exception)" do
      {exception, tags} =
        capture_appsignal(fn ->
          assert_raise RuntimeError, fn ->
            Instrumentation.around(StubWebhook, %{organization_id: 1}, fn ->
              raise RuntimeError, "webhook blew up"
            end)
          end
        end)

      assert %Errors.SystemError{} = exception
      assert tags.error_type == "exception"
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
      assert exception.message == "Webhook callback failure"
      assert tags.organization_id == 1
      assert tags.webhook_name == "kaapi_asr"
      assert tags.reason == "ASR failed"
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

  # Config-vs-system routing for SYNC nodes: a typed `{:error, ErrorType.t(), msg}` return is
  # mapped by Instrumentation → ErrorReporter to the right namespace. The node owns the verdict;
  # there is no central heuristic. (Async / Kaapi classification is a separate, later change.)
  describe "ErrorReporter routing (sync)" do
    test "typed config failure → ConfigurationError under the config namespace" do
      {exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, %{organization_id: 1}, fn ->
            {:error, :invalid_geocoding, "Invalid geocoding request. Invalid 'latlng' parameter."}
          end)
        end)

      assert %Errors.ConfigurationError{} = exception
      assert tags.error_type == "invalid_geocoding"
    end

    test "typed system failure → SystemError under the system namespace" do
      {exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, %{organization_id: 1}, fn ->
            {:error, :missing_api_key, "Geocoding request was denied."}
          end)
        end)

      assert %Errors.SystemError{} = exception
      assert tags.error_type == "missing_api_key"
    end

    test "untyped sync failure fails safe to :unknown (system)" do
      {exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, %{organization_id: 1}, fn ->
            {:error, "some failure the node did not classify"}
          end)
        end)

      assert %Errors.SystemError{} = exception
      assert tags.error_type == "unknown"
    end

    test "typed upstream-blip failure reports a system incident (no retry — a blip is a real failure)" do
      {exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, %{organization_id: 1}, fn ->
            {:error, :rate_limited, "Geocoding quota exceeded."}
          end)
        end)

      assert %Errors.SystemError{} = exception
      assert tags.error_type == "rate_limited"
    end

    test "a malformed 3-tuple failure is still reported (not counted-but-invisible)" do
      {exception, tags} =
        capture_appsignal(fn ->
          Instrumentation.around(StubWebhook, %{organization_id: 1}, fn ->
            {:error, :some_type, %{not: "a binary"}}
          end)
        end)

      assert %Errors.SystemError{} = exception
      assert tags.error_type == "unknown"
    end
  end

  # Real-webhook failure reporting: a failing sync webhook dispatched through the framework
  # surfaces the right exception (config vs system) to AppSignal with the right tags
  # (webhook_name / organization_id / reason). Complements the stub-based around/3 tests above.
  describe "Instrumentation reporting — real sync webhooks" do
    test "reports a config error when parse_via_chat_gpt gets empty input" do
      {exception, tags} =
        capture_appsignal(fn ->
          assert Dispatcher.dispatch("parse_via_chat_gpt", %{"organization_id" => 1}) ==
                   "question_text is empty"
        end)

      assert %Errors.ConfigurationError{} = exception
      assert tags.webhook_name == "parse_via_chat_gpt"
      assert tags.organization_id == 1
      assert tags.reason == "question_text is empty"
      assert tags.error_type == "empty_input"
    end

    test "reports SystemError when parse_via_gpt_vision fails on invalid response_format" do
      fields = %{
        "organization_id" => 1,
        "url" => "https://example.com/image.jpg",
        "response_format" => %{"type" => "json_objectz"}
      }

      with_mock(Messages, validate_media: fn _, _ -> %{is_valid: true, message: "success"} end) do
        Tesla.Mock.mock(fn
          %{method: :get} ->
            %Tesla.Env{
              status: 200,
              body: "image-bytes",
              headers: [{"content-type", "image/jpeg"}]
            }
        end)

        {exception, tags} =
          capture_appsignal(fn ->
            assert Dispatcher.dispatch("parse_via_gpt_vision", fields) ==
                     "response_format type should be json_schema or json_object"
          end)

        assert %Errors.SystemError{} = exception
        assert tags.webhook_name == "parse_via_gpt_vision"
        assert tags.organization_id == 1
        assert tags.reason == "response_format type should be json_schema or json_object"
      end
    end

    test "reports a config error when parse_via_gpt_vision gets an invalid media URL" do
      with_mock(Messages,
        validate_media: fn _, _ -> %{is_valid: false, message: "Media URL is invalid"} end
      ) do
        {exception, tags} =
          capture_appsignal(fn ->
            assert Dispatcher.dispatch("parse_via_gpt_vision", %{
                     "organization_id" => 1,
                     "url" => "not-an-image"
                   }) == "Media URL is invalid"
          end)

        assert %Errors.ConfigurationError{} = exception
        assert tags.webhook_name == "parse_via_gpt_vision"
        assert tags.organization_id == 1
        assert tags.reason == "Media URL is invalid"
        assert tags.error_type == "invalid_media_url"
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
