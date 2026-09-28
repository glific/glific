defmodule Glific.CachesTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Caches,
    Fixtures
  }

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

    test "fetch/3 returns an error when the fallback exits and keeps the key fetchable" do
      organization_id = Fixtures.get_org_id()
      key = "exiting fallback key"

      assert {:error, error} =
               Caches.fetch(organization_id, key, fn _ -> exit(:db_checkout_failed) end)

      assert error =~ "Cache fallback exited"

      assert {:commit, "loaded"} =
               Caches.fetch(organization_id, key, fn _ -> {:commit, "loaded"} end)

      assert {:ok, "loaded"} == Caches.get(organization_id, key)
    end

    test "fetch/3 keeps the key fetchable when a linked process in the fallback crashes" do
      organization_id = Fixtures.get_org_id()
      key = "linked crash fallback key"

      crashing_fallback = fn _ ->
        fn -> exit(:db_owner_exited) end
        |> Task.async()
        |> Task.await()
      end

      assert {:error, error} = Caches.fetch(organization_id, key, crashing_fallback)
      assert error =~ "Cache fallback exited"

      assert {:commit, "loaded"} =
               Caches.fetch(organization_id, key, fn _ -> {:commit, "loaded"} end)
    end
  end
end
