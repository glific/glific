defmodule Glific.Flows.WakeupWorkerTest do
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Repo
  }

  alias Glific.Flows.{
    Flow,
    FlowContext,
    WakeupWorker
  }

  # keep in sync with @wake_up_flow_limit in Glific.Flows.WakeupWorker
  @wake_up_flow_limit 200

  @valid_attrs %{
    flow_id: 1,
    flow_uuid: Ecto.UUID.generate(),
    uuid_map: %{},
    node_uuid: Ecto.UUID.generate()
  }

  defp flow_context_fixture(attrs) do
    contact = Fixtures.contact_fixture()

    {:ok, flow_context} =
      attrs
      |> Map.put(:contact_id, contact.id)
      |> Map.put(:organization_id, contact.organization_id)
      |> Enum.into(@valid_attrs)
      |> FlowContext.create_flow_context()

    flow_context
    |> Repo.preload(:contact)
    |> Repo.preload(:flow)
  end

  describe "WakeupWorker.perform/1" do
    test "processes all overdue contexts for the organization when under the batch limit",
         %{organization_id: organization_id} = _attrs do
      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "help"})
      [node | _tail] = flow.nodes

      three_minutes_ago = Timex.shift(Timex.now(), minutes: -3)

      first_context =
        flow_context_fixture(%{
          node_uuid: node.uuid,
          wakeup_at: three_minutes_ago,
          flow_uuid: flow.uuid,
          flow_id: flow.id
        })

      second_context =
        flow_context_fixture(%{
          node_uuid: node.uuid,
          wakeup_at: three_minutes_ago,
          flow_uuid: flow.uuid,
          flow_id: flow.id
        })

      assert :ok = perform_job(WakeupWorker, %{organization_id: organization_id})

      {:ok, reloaded_first_context} = Repo.fetch_by(FlowContext, %{id: first_context.id})
      {:ok, reloaded_second_context} = Repo.fetch_by(FlowContext, %{id: second_context.id})

      assert reloaded_first_context.wakeup_at == nil
      assert reloaded_second_context.wakeup_at == nil
    end

    test "only processes up to the batch limit, leaving the rest overdue for the next job",
         %{organization_id: organization_id} = _attrs do
      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "help"})
      [node | _tail] = flow.nodes

      three_minutes_ago = Timex.shift(Timex.now(), minutes: -3)

      contexts =
        for _ <- 1..(@wake_up_flow_limit + 1) do
          flow_context_fixture(%{
            node_uuid: node.uuid,
            wakeup_at: three_minutes_ago,
            flow_uuid: flow.uuid,
            flow_id: flow.id
          })
        end

      assert :ok = perform_job(WakeupWorker, %{organization_id: organization_id})

      reloaded_contexts =
        Enum.map(contexts, fn context ->
          {:ok, reloaded_context} = Repo.fetch_by(FlowContext, %{id: context.id})
          reloaded_context
        end)

      processed_count = Enum.count(reloaded_contexts, &is_nil(&1.wakeup_at))
      still_overdue_count = Enum.count(reloaded_contexts, &(not is_nil(&1.wakeup_at)))

      assert processed_count == @wake_up_flow_limit
      assert still_overdue_count == 1
    end

    test "leaves a context alone whose alarm hasn't gone off yet",
         %{organization_id: organization_id} = _attrs do
      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "help"})
      [node | _tail] = flow.nodes

      five_minutes_from_now = Timex.shift(Timex.now(), minutes: 5)

      flow_context =
        flow_context_fixture(%{
          node_uuid: node.uuid,
          wakeup_at: five_minutes_from_now,
          flow_uuid: flow.uuid,
          flow_id: flow.id
        })

      assert :ok = perform_job(WakeupWorker, %{organization_id: organization_id})

      {:ok, reloaded_flow_context} = Repo.fetch_by(FlowContext, %{id: flow_context.id})

      assert reloaded_flow_context.wakeup_at != nil
    end

    test "leaves a context alone that is already marked completed",
         %{organization_id: organization_id} = _attrs do
      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "help"})
      [node | _tail] = flow.nodes

      three_minutes_ago = Timex.shift(Timex.now(), minutes: -3)

      flow_context =
        flow_context_fixture(%{
          node_uuid: node.uuid,
          wakeup_at: three_minutes_ago,
          completed_at: Timex.now(),
          flow_uuid: flow.uuid,
          flow_id: flow.id
        })

      assert :ok = perform_job(WakeupWorker, %{organization_id: organization_id})

      {:ok, reloaded_flow_context} = Repo.fetch_by(FlowContext, %{id: flow_context.id})

      assert DateTime.truncate(reloaded_flow_context.wakeup_at, :second) ==
               DateTime.truncate(three_minutes_ago, :second)
    end
  end
end
