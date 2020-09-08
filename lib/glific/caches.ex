defmodule Glific.Caches do
  @moduledoc """
  Glific Cache management
  """
  @cache_bucket :glific_cache

  @behaviour Glific.Caches.CacheBehaviour

  @doc """
  Store all the in cachex :flows_cache. At some point, we will just use this dynamically
  """
  @impl Glific.Caches.CacheBehaviour
  @spec set(list(), (any() -> any()), map()) :: {:ok, any()}
  def set(keys, process_fn, args), do: set_to_cache(keys, process_fn.(args))

  @doc false
  @impl Glific.Caches.CacheBehaviour
  @spec set(list(), any()) :: {:ok, any()}
  def set(keys, value) when is_list(keys), do: set_to_cache(keys, value)

  @doc false
  @impl Glific.Caches.CacheBehaviour
  @spec set(String.t() | atom(), any()) :: {:ok, any()}
  def set(key, value), do: set_to_cache([key], value)

  @doc false
  @spec set_to_cache(list(), any) :: {:ok, any()}
  defp set_to_cache(keys, value) do
    keys = Enum.reduce(keys, [], fn key, acc -> [{key, value} | acc] end)
    {:ok, true} = Cachex.put_many(@cache_bucket, keys)
    {:ok, value}
  end

  @doc """
  Get a cached value based on a key
  """
  @impl Glific.Caches.CacheBehaviour
  @spec get(String.t() | atom()) :: {:ok, any()} | {:ok, false}
  def get(key) do
    case Cachex.exists?(@cache_bucket, key) do
      {:ok, true} -> Cachex.get(@cache_bucket, key)
      _ -> {:ok, false}
    end
  end

  @doc """
  Remove a value from the cache
  """
  @impl Glific.Caches.CacheBehaviour
  @spec remove(list()) :: any()
  def remove(keys),
    do:
      Enum.map(keys, fn key ->
        {:ok, _} = Cachex.del(@cache_bucket, key)
      end)
end
