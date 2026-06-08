defmodule Glific.Flows.Webhooks.SendWaGroupPollTest do
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  import Ecto.Query, warn: false

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.FlowContext,
    Flows.FlowRevision,
    Flows.Webhook,
    Flows.WebhookLog,
    Partners,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)

    Partners.create_credential(%{
      organization_id: 1,
      shortcode: "maytapi",
      keys: %{},
      secrets: %{
        "product_id" => "3fa22108-f464-41e5-81d9-d8a298854430",
        "token" => "f4f38e00-3a50-4892-99ce-a282fe24d041"
      },
      is_active: true
    })

    Partners.get_organization!(1) |> Partners.fill_cache()
    :ok
  end

  defp build_wa_group_context(attrs) do
    wa_phone = Fixtures.wa_managed_phone_fixture(attrs)

    flow = Fixtures.flow_fixture(%{name: "polls"})

    FlowRevision
    |> where([f], f.flow_id == ^flow.id)
    |> update([f], set: [status: "published"])
    |> Repo.update_all([])

    wa_group = Fixtures.wa_group_fixture(Map.put(attrs, :wa_managed_phone_id, wa_phone.id))

    flow_attrs = %{
      flow_id: flow.id,
      flow_uuid: flow.uuid,
      wa_group_id: wa_group.id,
      organization_id: attrs.organization_id
    }

    {:ok, context} = FlowContext.create_flow_context(flow_attrs)
    context = Repo.preload(context, [:wa_group, :flow])

    {context, flow_attrs, wa_phone}
  end

  describe "send_wa_group_poll" do
    test "happy path - successfully sends poll to WA group", attrs do
      Tesla.Mock.mock(fn
        %{method: :post, url: "https://api.maytapi.com/api/" <> _} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "success" => true,
               "data" => %{
                 "chatId" => "120363238104@g.us",
                 "msgId" => "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d"
               }
             }
           }}
      end)

      poll = Fixtures.wa_poll_fixture(%{label: "poll_a"})
      {context, flow_attrs, _wa_phone} = build_wa_group_context(attrs)

      action = %Action{
        method: "FUNCTION",
        url: "send_wa_group_poll",
        headers: %{},
        body: Jason.encode!(%{wa_group: "@wa_group", poll_uuid: "#{poll.uuid}"})
      }

      assert Webhook.execute(action, context) == nil

      assert_enqueued(worker: Webhook, prefix: "global")

      [job] = all_enqueued(worker: Webhook, prefix: "global")
      assert job.queue == "webhook"

      Oban.drain_queue(queue: :webhook)

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
      assert log.status == "Success"
    end

    test "failure - poll UUID not found", attrs do
      nonexistent_poll_uuid = Ecto.UUID.generate()
      {context, flow_attrs, _wa_phone} = build_wa_group_context(attrs)

      action = %Action{
        method: "FUNCTION",
        url: "send_wa_group_poll",
        headers: %{},
        body: Jason.encode!(%{wa_group: "@wa_group", poll_uuid: nonexistent_poll_uuid})
      }

      assert Webhook.execute(action, context) == nil

      Oban.drain_queue(queue: :webhook)

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
      assert log.error != nil
    end
  end
end
