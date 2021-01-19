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

    test "set/3 with a list of keys will add result of the function as cache for multiple keys" do
      organization_id = Fixtures.get_org_id()
      key1 = "key 1"
      key2 = "key 2"
      value = "hel//lo"
      clean_string = "hello"

      assert {:ok, clean_string} ==
               Caches.set(organization_id, [key1, key2], &Glific.string_clean/1, value)

      {:ok, value1} = Caches.get(organization_id, key1)
      {:ok, value2} = Caches.get(organization_id, key2)
      assert value1 == value2
      assert clean_string == value1
      assert clean_string == value2
    end
  end
end
