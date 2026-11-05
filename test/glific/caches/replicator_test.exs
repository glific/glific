defmodule Glific.Caches.ReplicatorTest do
  use Glific.DataCase

  alias Glific.{
    Caches,
    Caches.Replicator,
    Fixtures
  }

  @topic "glific_cache"
  @other_node :"other@127.0.0.1"

  setup do
    Phoenix.PubSub.subscribe(Glific.PubSub, @topic)
    %{organization_id: Fixtures.get_org_id()}
  end

  test "set/4 sends the entries it wrote, with their ttl", %{organization_id: organization_id} do
    Caches.set(organization_id, "replicated key", "replicated value", ttl: :timer.minutes(5))

    assert_receive {Replicator, origin, {:put_many, entries, opts}}
    assert origin == node()
    assert {{organization_id, "replicated key"}, "replicated value"} in entries
    assert List.keymember?(entries, {organization_id, :cache_reload_key}, 0)
    assert opts[:ttl] == :timer.minutes(5)
  end

  test "remove/2 sends the keys it deleted", %{organization_id: organization_id} do
    Caches.remove(organization_id, ["removed key"])

    assert_receive {Replicator, _origin, {:delete, [{^organization_id, "removed key"}]}}
  end

  test "a write from another node is applied to the local cache", %{
    organization_id: organization_id
  } do
    broadcast_from(
      @other_node,
      {:put_many, [{{organization_id, "remote key"}, "remote value"}], []}
    )

    assert {:ok, "remote value"} == Caches.get(organization_id, "remote key")

    broadcast_from(@other_node, {:delete, [{organization_id, "remote key"}]})
    assert {:ok, false} == Caches.get(organization_id, "remote key")
  end

  test "a write from this node is not applied again", %{organization_id: organization_id} do
    broadcast_from(node(), {:put_many, [{{organization_id, "local key"}, "local value"}], []})
    assert {:ok, false} == Caches.get(organization_id, "local key")
  end

  test "a single replicator runs per node, started with the application" do
    assert {:error, {:already_started, pid}} = Replicator.start_link([])
    assert pid == Process.whereis(Replicator)
  end

  test "init/1 subscribes the replicator to the cache topic" do
    assert :subscribed ==
             fn -> init_and_receive() end
             |> Task.async()
             |> Task.await()
  end

  # an own-node message, which the running replicator ignores
  @probe {Replicator, node(), {:delete, []}}

  defp init_and_receive do
    {:ok, nil} = Replicator.init(nil)
    Phoenix.PubSub.broadcast(Glific.PubSub, @topic, @probe)

    receive do
      @probe -> :subscribed
    after
      1_000 -> :not_subscribed
    end
  end

  defp broadcast_from(origin, operation) do
    Phoenix.PubSub.broadcast(Glific.PubSub, @topic, {Replicator, origin, operation})
    # the broadcast is already in the replicator's mailbox, so this returns once it is applied
    :sys.get_state(Replicator)
  end
end
