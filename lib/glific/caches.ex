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
  @spec set(non_neg_integer, list(), (any() -> any()), map()) :: {:ok, any()}
  def set(organization_id, keys, process_fn, args),
    do: set_to_cache(organization_id, keys, process_fn.(args))

  @doc false
  @impl Glific.Caches.CacheBehaviour
  @spec set(non_neg_integer, any(), any()) :: {:ok, any()}
  def set(organization_id, keys, value) when is_list(keys),
    do: set_to_cache(organization_id, keys, value)

  @doc false
  @impl Glific.Caches.CacheBehaviour
  def set(organization_id, key, value), do: set_to_cache(organization_id, [key], value)

  @doc false
  @impl Glific.Caches.CacheBehaviour
  @spec set(String.t(), any()) :: {:ok, any()}
  def set(shortcode, value),
    do: set_to_cache(shortcode, value)

  @doc false
  @spec set_to_cache(non_neg_integer, list(), any) :: {:ok, any()}
  defp set_to_cache(organization_id, keys, value) do
    keys = Enum.reduce(keys, [], fn key, acc -> [{{organization_id, key}, value} | acc] end)

    # also update the reload key for consumers to refresh caches
    keys = [{{organization_id, :cache_reload_key}, Ecto.UUID.generate()} | keys]

    {:ok, true} = Cachex.put_many(@cache_bucket, keys)
    {:ok, value}
  end

  @doc false
  @spec set_to_cache(String.t(), any) :: {:ok, any()}
  def set_to_cache(shortcode, value) do
    # also update the reload key for consumers to refresh caches
    # keys = [{{organization_id, :cache_reload_key}, Ecto.UUID.generate()} | keys]

    {:ok, true} = Cachex.put(@cache_bucket, {"organizations_list", shortcode}, value)
    {:ok, value}
  end

  @doc """
  Get a cached value based on string as key
  """
  @impl Glific.Caches.CacheBehaviour
  @spec get(String.t()) :: {:ok, any()} | {:ok, false}
  def get(shortcode) do
    case Cachex.exists?(@cache_bucket, {"organizations_list", shortcode}) do
      {:ok, true} -> Cachex.get(@cache_bucket, {"organizations_list", shortcode})
      _ -> {:ok, false}
    end
  end

  @doc """
  Get a cached value based on a key
  """
  @impl Glific.Caches.CacheBehaviour
  @spec get(non_neg_integer, any()) :: {:ok, any()} | {:ok, false}
  def get(organization_id, key) do
    case Cachex.exists?(@cache_bucket, {organization_id, key}) do
      {:ok, true} -> Cachex.get(@cache_bucket, {organization_id, key})
      _ -> {:ok, false}
    end
  end

  @doc """
  Get a cached value based on a key with fallback
  """
  @impl Glific.Caches.CacheBehaviour
  @spec fetch(non_neg_integer, any(), (any() -> any())) :: {:ok, any()} | {:ok, false}
  def fetch(organization_id, key, fallback_fn) do
    Cachex.fetch(@cache_bucket, {organization_id, key}, fallback_fn)
  end

  @doc """
  Remove a value from the cache
  """
  @impl Glific.Caches.CacheBehaviour
  @spec remove(non_neg_integer, list()) :: any()
  def remove(organization_id, keys),
    do:
      Enum.map(keys, fn key ->
        {:ok, _} = Cachex.del(@cache_bucket, {organization_id, key})
      end)
end
