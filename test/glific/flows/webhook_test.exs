defmodule Glific.Flows.WebhookTest do
  use Glific.DataCase, async: true
  use Oban.Pro.Testing, repo: Glific.Repo

  import Mock

  alias Glific.Flows.{
    Action,
    FlowContext,
    FlowRevision,
    Webhook,
    WebhookLog
  }

  alias Glific.{
    Fixtures,
    Partners,
    Seeds.SeedsDev
  }

  alias Glific.ThirdParty.Kaapi

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    :ok
  end

  describe "webhook" do
    @results %{
      "content" => "Your score: 31 is not divisible by 2, 3, 5 or 7",
      "score" => "31",
      "status" => "5"
    }
    @results_as_list [
      %{
        "content" => "Your score: 31 is not divisible by 2, 3, 5 or 7",
        "score" => "31",
        "status" => "5",
        "list_key" => [
          %{
            "list_nest_key" => "list_nest_value"
          }
        ]
      }
    ]

    @action_body %{
      contact: "@contact",
      results: "@results",
      custom_key: "custom_value"
    }

    test "successful geolocation response" do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(@results)
          }
      end)
    end

    test "execute a webhook for post method should return the response body with results",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(@results)
          }
      end)

      attrs = %{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: Fixtures.contact_fixture(attrs).id,
        organization_id: attrs.organization_id
      }

      {:ok, context} = FlowContext.create_flow_context(attrs)
      context = Repo.preload(context, [:contact, :flow])

      action = %Action{
        headers: %{"Accept" => "application/json"},
        method: "POST",
        url: "some url",
        body: Jason.encode!(@action_body)
      }

      assert Webhook.execute(action, context) == nil

      assert_enqueued(worker: Webhook, prefix: "global")

      # we now need to wait for the Oban job and fire and then
      # check the results of the context
    end

    test "execute a webhook for GET method should return the response body with results",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(@results)
          }
      end)

      attrs = %{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: Fixtures.contact_fixture(attrs).id,
        organization_id: attrs.organization_id
      }

      {:ok, context} = FlowContext.create_flow_context(attrs)
      context = Repo.preload(context, [:contact, :flow])

      action = %Action{
        headers: %{"Accept" => "application/json"},
        method: "GET",
        url: "some url",
        body: Jason.encode!(@action_body)
      }

      assert Webhook.execute(action, context) == nil

      assert_enqueued(worker: Webhook, prefix: "global")

      # Warm the org cache before draining so Cachex's fallback DB query
      # doesn't fire from the Oban job's spawned process, which lacks sandbox ownership.
      Partners.organization(attrs.organization_id)

      Oban.drain_queue(queue: :webhook)

      webhook_log = List.first(WebhookLog.list_webhook_logs(%{filter: attrs}))
      assert webhook_log.status == "Success"
    end

    test "execute a webhook for GET method with empty body should return the response body with results",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(@results)
          }
      end)

      attrs = %{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: Fixtures.contact_fixture(attrs).id,
        organization_id: attrs.organization_id
      }

      {:ok, context} = FlowContext.create_flow_context(attrs)
      context = Repo.preload(context, [:contact, :flow])

      action = %Action{
        headers: %{"Accept" => "application/json"},
        method: "GET",
        url: "url with no body",
        body: Jason.encode!(%{})
      }

      assert Webhook.execute(action, context) == nil

      assert_enqueued(worker: Webhook, prefix: "global")
      Oban.drain_queue(queue: :webhook)

      webhook_log = List.first(WebhookLog.list_webhook_logs(%{filter: attrs}))
      assert webhook_log.status == "Success"
    end

    test "execute a webhook for post method should not break and update the webhook log in case of error",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 404,
            body: ""
          }
      end)

      attrs = %{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: Fixtures.contact_fixture(attrs).id,
        organization_id: attrs.organization_id
      }

      {:ok, context} = FlowContext.create_flow_context(attrs)
      context = Repo.preload(context, [:contact, :flow])
      contact_id = context.contact.id

      action = %Action{
        headers: %{"Accept" => "application/json", "custom_header" => "@contact.id"},
        method: "POST",
        url: "www.one.com/@contact.id",
        body: Jason.encode!(@action_body)
      }

      assert Webhook.execute(action, context) == nil
      webhook_log = List.first(WebhookLog.list_webhook_logs(%{filter: attrs}))

      assert webhook_log.request_headers["custom_header"] == Integer.to_string(contact_id)
      assert webhook_log.url == "www.one.com/#{contact_id}"
    end

    test "execute a webhook for post method should not break and update the webhook log in case of array/list response",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(@results_as_list)
          }
      end)

      attrs = %{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: Fixtures.contact_fixture(attrs).id,
        organization_id: attrs.organization_id
      }

      {:ok, context} = FlowContext.create_flow_context(attrs)
      context = Repo.preload(context, [:contact, :flow])

      action = %Action{
        headers: %{"Accept" => "application/json"},
        method: "POST",
        url: "some url",
        body: Jason.encode!(@action_body)
      }

      assert Webhook.execute(action, context) == nil
      Oban.drain_queue(queue: :webhook)

      webhook_log = List.first(WebhookLog.list_webhook_logs(%{filter: attrs}))

      response = webhook_log.response_json

      assert get_in(response, ["0", "list_key", "0", "list_nest_key"]) == "list_nest_value"
    end
  end

  describe "webhook logs" do
    @valid_attrs %{
      url: "some url",
      method: "GET",
      request_headers: %{
        "Accept" => "application/json",
        "X-Glific-Signature" => "random signature"
      },
      request_json: %{}
    }
    @update_attrs %{
      response_json: %{},
      status_code: 200
    }

    test "create_webhook_log/1 with valid data creates a webhook_log",
         %{organization_id: _organization_id} = attrs do
      flow = Fixtures.flow_fixture(attrs)
      contact = Fixtures.contact_fixture(attrs)

      valid_attrs =
        @valid_attrs
        |> Map.put(:contact_id, contact.id)
        |> Map.put(:flow_id, flow.id)
        |> Map.put(:organization_id, flow.organization_id)

      assert {:ok, %WebhookLog{}} = WebhookLog.create_webhook_log(valid_attrs)
    end

    test "create_webhook_log/1 with valid data creates a webhook_log for wa_group",
         %{organization_id: _organization_id} = attrs do
      flow = Fixtures.flow_fixture(attrs)
      wa_phone = Fixtures.wa_managed_phone_fixture(attrs)
      wa_group = Fixtures.wa_group_fixture(Map.put(attrs, :wa_managed_phone_id, wa_phone.id))

      valid_attrs =
        @valid_attrs
        |> Map.put(:wa_group_id, wa_group.id)
        |> Map.put(:flow_id, flow.id)
        |> Map.put(:organization_id, flow.organization_id)

      assert {:ok, %WebhookLog{}} = WebhookLog.create_webhook_log(valid_attrs)
    end

    test "update_webhook_log/2 with valid data updates the webhook_log", attrs do
      flow = Fixtures.flow_fixture(attrs)
      contact = Fixtures.contact_fixture(attrs)

      valid_attrs =
        @valid_attrs
        |> Map.put(:contact_id, contact.id)
        |> Map.put(:flow_id, flow.id)
        |> Map.put(:organization_id, flow.organization_id)

      {:ok, webhook_log} = WebhookLog.create_webhook_log(valid_attrs)

      assert {:ok, %WebhookLog{} = webhook_log} =
               WebhookLog.update_webhook_log(webhook_log, @update_attrs)

      assert webhook_log.status_code == 200
    end

    test "list_webhook_logs/2", attrs do
      webhook_log = Fixtures.webhook_log_fixture(attrs)

      assert [Map.merge(webhook_log, %{status: "Success"})] ==
               WebhookLog.list_webhook_logs(%{filter: attrs})
    end

    test "list_webhook_logs/2 returns filtered logs", attrs do
      webhook_log_1 = Fixtures.webhook_log_fixture(attrs)
      :timer.sleep(1000)

      valid_attrs_2 = Map.merge(attrs, %{url: "test_url_2", status_code: 500})
      webhook_log_2 = Fixtures.webhook_log_fixture(valid_attrs_2)

      assert [Map.merge(webhook_log_2, %{status: "Error"})] ==
               WebhookLog.list_webhook_logs(%{filter: %{status_code: 500}})

      assert [Map.merge(webhook_log_1, %{status: "Success"})] ==
               WebhookLog.list_webhook_logs(%{filter: %{status_code: 200, status: "Success"}})

      assert [Map.merge(webhook_log_1, %{status: "Success"})] ==
               WebhookLog.list_webhook_logs(%{filter: %{url: @valid_attrs.url}})

      #  order by inserted at
      assert [
               Map.merge(webhook_log_2, %{status: "Error"}),
               Map.merge(webhook_log_1, %{status: "Success"})
             ] ==
               WebhookLog.list_webhook_logs(%{opts: %{order: :desc}, filter: attrs})

      #  filter by contact_phone

      webhook_log = webhook_log_1 |> Repo.preload([:contact])
      phone = webhook_log.contact.phone

      assert [
               Map.merge(webhook_log_1, %{status: "Success"})
             ] ==
               WebhookLog.list_webhook_logs(%{
                 filter: %{contact_phone: phone}
               })
    end

    test "count_webhook_logs/0 returns count of all webhook logs", attrs do
      logs_count = WebhookLog.count_webhook_logs(%{filter: attrs})

      Fixtures.webhook_log_fixture(attrs)

      assert WebhookLog.count_webhook_logs(%{filter: attrs}) == logs_count + 1
    end
  end

  describe "Webhook.update_log/2 failure handling" do
    test "records %{success: false, reason: _} as status 400 with the reason as error", attrs do
      webhook_log = Fixtures.webhook_log_fixture(attrs)
      result = %{success: false, reason: "Kaapi STT failed"}

      assert {:ok, log} = Webhook.update_log(webhook_log, result)
      assert log.status_code == 400
      assert log.error == "Kaapi STT failed"
      assert log.response_json == result
    end

    test "falls back to :error when :reason is absent", attrs do
      webhook_log = Fixtures.webhook_log_fixture(attrs)
      result = %{success: false, error: "Bad input"}

      assert {:ok, log} = Webhook.update_log(webhook_log, result)
      assert log.status_code == 400
      assert log.error == "Bad input"
    end

    test "falls back to :message when :reason and :error are absent", attrs do
      webhook_log = Fixtures.webhook_log_fixture(attrs)
      result = %{success: false, message: "Something went wrong"}

      assert {:ok, log} = Webhook.update_log(webhook_log, result)
      assert log.status_code == 400
      assert log.error == "Something went wrong"
    end

    test "defaults to a generic error when no reason-like field is present", attrs do
      webhook_log = Fixtures.webhook_log_fixture(attrs)
      result = %{success: false}

      assert {:ok, log} = Webhook.update_log(webhook_log, result)
      assert log.status_code == 400
      assert log.error == "Webhook failure"
    end

    test "leaves success maps as status 200 with no error", attrs do
      webhook_log = Fixtures.webhook_log_fixture(attrs)
      result = %{success: true, parsed_msg: "ok"}

      assert {:ok, log} = Webhook.update_log(webhook_log, result)
      assert log.status_code == 200
      assert log.error == nil
    end

    test "treats a map without a success key as a 200 response(for get_buttons and check_response webhook)",
         attrs do
      webhook_log = Fixtures.webhook_log_fixture(attrs)
      result = %{response: "ok", extra: 1}

      assert {:ok, log} = Webhook.update_log(webhook_log, result)
      assert log.status_code == 200
      assert log.error == nil
    end

    test "handles non-binary reason (e.g. a decoded JSON map) without crashing", attrs do
      webhook_log = Fixtures.webhook_log_fixture(attrs)
      # Bhasini sets %{success: false, reason: body} on a 500 with body being a
      # decoded JSON map. to_string/1 would raise on that; the cond path uses
      # inspect/1 instead so the log row still gets written.
      result = %{success: false, reason: %{"error" => "upstream blew up"}}

      assert {:ok, log} = Webhook.update_log(webhook_log, result)
      assert log.status_code == 400
      assert is_binary(log.error)
      assert String.contains?(log.error, "upstream blew up")
    end
  end

  test "execute a webhook with a POST request, consecutive webhook calls should not work",
       attrs do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: Jason.encode!(@results)
        }
    end)

    attrs = %{
      flow_id: 1,
      flow_uuid: Ecto.UUID.generate(),
      contact_id: Fixtures.contact_fixture(attrs).id,
      organization_id: attrs.organization_id
    }

    {:ok, context} = FlowContext.create_flow_context(attrs)
    context = Repo.preload(context, [:contact, :flow])

    action = %Action{
      headers: %{"Accept" => "application/json"},
      method: "POST",
      url: "some url",
      body: Jason.encode!(@action_body)
    }

    assert Webhook.execute(action, context) == nil
    assert Webhook.execute(action, context) == nil
    jobs = all_enqueued(worker: Webhook, prefix: "global")
    # although we had 2 webhook calls, only 1 job got enqueued
    assert 1 == length(jobs)
  end

  test "execute a webhook where url is parse_via_gpt_vision, consecutive webhook calls should work",
       attrs do
    Tesla.Mock.mock(fn
      %{url: "https://api.openai.com/v1/chat/completions"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            "choices" => [
              %{
                "message" => %{
                  "content" => "{\"maximum_value\":\"10\",\"minimum_value\":\"1\"}"
                }
              }
            ]
          }
        }
    end)

    attrs = %{
      flow_id: 1,
      flow_uuid: Ecto.UUID.generate(),
      contact_id: Fixtures.contact_fixture(attrs).id,
      organization_id: attrs.organization_id
    }

    {:ok, context} = FlowContext.create_flow_context(attrs)
    context = Repo.preload(context, [:contact, :flow])

    action = %Action{
      headers: %{"Accept" => "application/json"},
      method: "FUNCTION",
      url: "parse_via_gpt_vision",
      body: Jason.encode!(@action_body)
    }

    assert Webhook.execute(action, context) == nil
    assert Webhook.execute(action, context) == nil

    [%{priority: 0, queue: "gpt_webhook_queue"} | _] =
      jobs = all_enqueued(worker: Webhook, prefix: "global")

    assert 2 == length(jobs)
  end

  test "execute a webhook where url is geolocation, consecutive webhook calls should not work",
       attrs do
    Tesla.Mock.mock(fn
      %{method: :get} ->
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

    attrs = %{
      flow_id: 1,
      flow_uuid: Ecto.UUID.generate(),
      contact_id: Fixtures.contact_fixture(attrs).id,
      organization_id: attrs.organization_id
    }

    {:ok, context} = FlowContext.create_flow_context(attrs)
    context = Repo.preload(context, [:contact, :flow])

    action = %Action{
      headers: %{"Accept" => "application/json"},
      method: "FUNCTION",
      url: "geolocation",
      body: Jason.encode!(@action_body)
    }

    assert Webhook.execute(action, context) == nil
    assert Webhook.execute(action, context) == nil
    jobs = all_enqueued(worker: Webhook, prefix: "global")
    # although we had 2 webhook calls for geolocation, only 1 job got enqueued
    assert 1 == length(jobs)
  end

  test "execute a webhook function send_wa_group_poll",
       attrs do
    wa_phone = Fixtures.wa_managed_phone_fixture(attrs)
    flow = Fixtures.flow_fixture(%{name: "polls"})

    FlowRevision
    |> where([f], f.flow_id == ^flow.id)
    |> update([f], set: [status: "published"])
    |> Repo.update_all([])

    attrs = %{
      flow_id: flow.id,
      flow_uuid: flow.uuid,
      wa_group_id:
        Fixtures.wa_group_fixture(attrs |> Map.put(:wa_managed_phone_id, wa_phone.id)).id,
      organization_id: attrs.organization_id
    }

    poll = Fixtures.wa_poll_fixture(%{label: "poll_a"})

    action_body = %{
      wa_group: "@wa_group",
      poll_uuid: "#{poll.uuid}"
    }

    {:ok, context} = FlowContext.create_flow_context(attrs)
    context = Repo.preload(context, [:wa_group, :flow])

    action = %Action{
      headers: %{"Accept" => "application/json"},
      method: "FUNCTION",
      url: "send_wa_group_poll",
      body: Jason.encode!(action_body)
    }

    assert Webhook.execute(action, context) == nil
    jobs = all_enqueued(worker: Webhook, prefix: "global")
    assert 1 == length(jobs)
  end

  test "after executing a webhook the uuids_seen value should be preserved",
       attrs do
    Tesla.Mock.mock(fn
      %{url: "https://api.openai.com/v1/chat/completions"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            "choices" => [
              %{
                "message" => %{
                  "content" => "{\"maximum_value\":\"10\",\"minimum_value\":\"1\"}"
                }
              }
            ]
          }
        }
    end)

    flow_uuid = Ecto.UUID.generate()

    attrs = %{
      flow_id: 1,
      flow_uuid: flow_uuid,
      contact_id: Fixtures.contact_fixture(attrs).id,
      organization_id: attrs.organization_id
    }

    {:ok, context} = FlowContext.create_flow_context(attrs)

    context =
      context
      |> Repo.preload([:contact, :flow])
      |> Map.put(:uuids_seen, %{flow_uuid => 1})

    action = %Action{
      headers: %{"Accept" => "application/json"},
      method: "FUNCTION",
      url: "parse_via_gpt_vision",
      body: Jason.encode!(@action_body)
    }

    assert Webhook.execute(action, context) == nil
    [job] = all_enqueued(worker: Webhook, prefix: "global")
    assert job.queue == "gpt_webhook_queue"
    context_map = job.args["context"]
    assert context_map["uuids_seen"] == %{flow_uuid => 1}
  end

  test "custom_certificate webhook should run in its own queue",
       attrs do
    flow_uuid = Ecto.UUID.generate()

    attrs = %{
      flow_id: 1,
      flow_uuid: flow_uuid,
      contact_id: Fixtures.contact_fixture(attrs).id,
      organization_id: attrs.organization_id
    }

    {:ok, context} = FlowContext.create_flow_context(attrs)

    context =
      context
      |> Repo.preload([:contact, :flow])
      |> Map.put(:uuids_seen, %{flow_uuid => 1})

    action = %Action{
      headers: %{"Accept" => "application/json"},
      method: "FUNCTION",
      url: "create_certificate",
      body:
        Jason.encode!(%{
          certificate_id: 1,
          results: "@results"
        })
    }

    assert Webhook.execute(action, context) == nil
    [job] = all_enqueued(worker: Webhook, prefix: "global")
    assert job.queue == "custom_certificate"
  end

  test "nmt_tts webhook should run with lower priority",
       attrs do
    flow_uuid = Ecto.UUID.generate()

    attrs = %{
      flow_id: 1,
      flow_uuid: flow_uuid,
      contact_id: Fixtures.contact_fixture(attrs).id,
      organization_id: attrs.organization_id
    }

    {:ok, context} = FlowContext.create_flow_context(attrs)

    context =
      context
      |> Repo.preload([:contact, :flow])
      |> Map.put(:uuids_seen, %{flow_uuid => 1})

    action = %Action{
      headers: %{"Accept" => "application/json"},
      method: "FUNCTION",
      url: "nmt_tts_with_bhasini",
      body: Jason.encode!(%{})
    }

    assert Webhook.execute(action, context) == nil
    [job] = all_enqueued(worker: Webhook, prefix: "global")
    assert job.queue == "gpt_webhook_queue"
    assert job.priority == 2
  end

  describe "execute_unified_voice_filesearch/2 failure reporting" do
    setup do
      {:ok, _credential} =
        Partners.create_credential(%{
          organization_id: 1,
          shortcode: "kaapi",
          keys: %{},
          secrets: %{"api_key" => "sk_test_key"},
          is_active: true
        })

      Partners.get_organization!(1) |> Partners.fill_cache()
      :ok
    end

    test "catches a raised exception, reports it to AppSignal, and reraises it" do
      test_pid = self()

      # With Kaapi creds present, unified_llm_and_wait injects the API key via
      # Map.put(action.headers, ...). A nil headers map raises BadMapError -- exactly
      # the kind of unexpected failure with_failure_reporting must catch and report.
      action = %Action{headers: nil, method: "FUNCTION", url: "voice-filesearch-gpt", body: "{}"}
      context = %FlowContext{organization_id: 1}

      with_mocks([
        {Kaapi, [],
         [
           fetch_kaapi_creds: fn _org_id -> {:ok, %{"api_key" => "sk_test_key"}} end
         ]},
        {Appsignal, [:passthrough],
         [
           send_error: fn exception, _stack, configurator ->
             send(test_pid, {:appsignal_exception, exception})
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
        # The original exception is reraised after the failure is reported.
        assert_raise BadMapError, fn ->
          Webhook.execute_unified_voice_filesearch(action, context)
        end
      end

      assert_receive {:appsignal_exception,
                      %Webhook.SystemError{
                        message: "Webhook system_error from unified-voice-llm-call"
                      }}

      assert_receive {:appsignal_tag, "tags", tags}
      assert tags.organization_id == 1
      assert tags.webhook_name == "unified-voice-llm-call"
      assert tags.reason =~ "map"
    end
  end
end
