defmodule Glific.Flows.WebhookTest do
  use Glific.DataCase, async: true
  use Oban.Testing, repo: Glific.Repo

  alias Glific.Flows.{
    Action,
    FlowContext,
    FlowRevision,
    Webhook,
    WebhookLog
  }

  alias Glific.{
    Fixtures,
    Seeds.SeedsDev
  }

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
end
