defmodule Glific.CachesTest do
  use Glific.DataCase, async: true

  import ExUnit.CaptureLog

  alias Glific.{
    Caches,
    Fixtures
  }

  describe "fetch/3" do
    # Cachex runs a fetch fallback in a process its Courier bare-spawns, which owns no SQL
    # Sandbox connection and propagates no $callers. This test is async, so no shared mode
    # exists for it to borrow either — the same missing ownership that, under a sync test,
    # kills the fallback mid-query and wedges the key for the rest of the run.
    test "loads through a fallback that queries the database" do
      organization_id = Fixtures.get_org_id()

      loader = fn _cache_key ->
        {:commit, Glific.Partners.get_organization!(organization_id).shortcode}
      end

      assert {:commit, shortcode} = Caches.fetch(organization_id, "fetch db loader", loader)
      assert is_binary(shortcode)
    end


    test "a fallback that exits errors out and leaves the key fetchable" do
      organization_id = Fixtures.get_org_id()
      key = "fetch exiting loader"

      capture_log(fn ->
        assert {:error, _reason} = Caches.fetch(organization_id, key, fn _ -> exit(:boom) end)
      end)

      retry =
        Task.async(fn -> Caches.fetch(organization_id, key, fn _ -> {:commit, "recovered"} end) end)

      assert {:ok, {:commit, "recovered"}} =
               Task.yield(retry, 5_000) || Task.shutdown(retry, :brutal_kill)
    end
  end

  describe "caches" do
    test "set/2 with a single key will generate the cache" do
      organization_id = Fixtures.get_org_id()
      key = "key 1"
      value = "Cached Value"
      assert {:ok, value} == Caches.set(organization_id, key, value)
      {:ok, cached_value} = Caches.get(organization_id, key)
      assert cached_value == value
    end

    test "set/2 with a list of keys will add cache for multiple keys" do
      organization_id = Fixtures.get_org_id()
      key1 = "key 1"
      key2 = "key 2"
      value = "Cached Value"
      assert {:ok, value} == Caches.set(organization_id, [key1, key2], value)
      {:ok, value1} = Caches.get(organization_id, key1)
      {:ok, value2} = Caches.get(organization_id, key2)
      assert value1 == value2
    end

    test "get/1 will return a touple with the cached value" do
      organization_id = Fixtures.get_org_id()
      key = "key 1"
      value = "Cached Value"
      assert {:ok, value} == Caches.set(organization_id, key, value)
      assert {:ok, cached_value} = Caches.get(organization_id, key)
      assert cached_value == value
    end

    test "remove/1 will remove a cache for the given list of keys" do
      organization_id = Fixtures.get_org_id()
      key1 = "key 1"
      key2 = "key 2"
      value = "Cached Value"
      Caches.set(organization_id, [key1, key2], value)
      Caches.remove(organization_id, [key1, key2])
      assert {:ok, false} == Caches.get(organization_id, key1)
      assert {:ok, false} == Caches.get(organization_id, key2)
    end
  end
end
