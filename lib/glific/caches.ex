defmodule Glific.Caches do
  @moduledoc """
  Glific Cache management
  """
  alias Glific.SafeLog

  @cache_bucket :glific_cache

  @behaviour Glific.Caches.CacheBehaviour

  # set timer limit
  @ttl_limit 24

  @doc false
  @impl Glific.Caches.CacheBehaviour
  @spec set(non_neg_integer, any(), any(), Keyword.t()) :: {:ok, any()}
  def set(organization_id, key, value, opts \\ [])

  def set(organization_id, keys, value, opts) when is_list(keys),
    do: set_to_cache(organization_id, keys, value, opts)

  @impl Glific.Caches.CacheBehaviour
  def set(organization_id, key, value, opts),
    do: set_to_cache(organization_id, [key], value, opts)

  @doc false
  @spec set_to_cache(non_neg_integer, list(), any, Keyword.t()) :: {:ok, any()}
  defp set_to_cache(organization_id, keys, value, opts) do
    keys = Enum.reduce(keys, [], fn key, acc -> [{{organization_id, key}, value} | acc] end)

    # also update the reload key for consumers to refresh caches
    keys = [{{organization_id, :cache_reload_key}, Ecto.UUID.generate()} | keys]

    default_opts = [ttl: :timer.hours(@ttl_limit)]

    {:ok, true} = Cachex.put_many(@cache_bucket, keys, Keyword.merge(default_opts, opts))
    {:ok, value}
  end

  @doc """
  Get a cached value based on a key
  """
  @impl Glific.Caches.CacheBehaviour
  @spec get(non_neg_integer, any(), Keyword.t()) :: {:ok, any()} | {:ok, false}
  def get(organization_id, key, opts \\ []) do
    case Cachex.exists?(@cache_bucket, {organization_id, key}) do
      {:ok, true} ->
        refresh_cache = Keyword.get(opts, :refresh_cache, true)
        if refresh_cache, do: Cachex.refresh(@cache_bucket, {organization_id, key})
        Cachex.get(@cache_bucket, {organization_id, key})

      _ ->
        {:ok, false}
    end
  end

  @doc """
  Get a cached value based on a key with fallback
  """
  @impl Glific.Caches.CacheBehaviour
  @spec fetch(non_neg_integer, any(), (any() -> any())) ::
          {:ok | :error | :commit | :ignore, any()}
  def fetch(organization_id, key, fallback_fn) do
    caller = self()

    Cachex.fetch(@cache_bucket, {organization_id, key}, fn cache_key ->
      try do
        allow_db_access(caller)
        fallback_fn.(cache_key)
      catch
        :exit, reason -> fallback_failed(key, :exit, reason)
        :throw, value -> fallback_failed(key, :throw, value)
      end
    end)
  end

  # Cachex's Courier bare-spawns the fallback and only `rescue`s it, so a fallback that *exits* —
  # a sandbox connection pulled out from under it, a GenServer.call timing out — never reports
  # back. The key then stays flagged in-flight for the life of the node and every later fetch of
  # it blocks forever on an :infinity call. Returning an error clears the flag so the next fetch
  # retries. Exceptions are deliberately left to the Courier's own rescue.
  @spec fallback_failed(any(), :exit | :throw, any()) :: {:error, String.t()}
  defp fallback_failed(key, kind, reason) do
    Glific.log_error(
      "Cache fallback for #{SafeLog.safe_inspect(key)} #{kind}ed: #{SafeLog.safe_inspect(reason)}"
    )
  end

  # Cachex runs a fetch fallback in a process its Courier bare-spawns, so the process propagates
  # no $callers and owns no SQL Sandbox connection. Its queries survive only by borrowing whatever
  # shared mode points at, and when that owner checks in mid-query the fallback *exits* — the
  # Courier only rescues exceptions, so it never reports back, the key stays flagged in-flight,
  # and every later fetch of it blocks forever on an :infinity call. The caller is parked on this
  # fetch and so cannot check in underneath the fallback, which makes it the one safe lender.
  if Application.compile_env(:glific, :environment) == :test do
    alias Ecto.Adapters.SQL.Sandbox

    @spec allow_db_access(pid()) :: any()
    defp allow_db_access(caller),
      do: Sandbox.allow(Glific.Repo, caller, self())
  else
    @spec allow_db_access(pid()) :: any()
    defp allow_db_access(_caller), do: :ok
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

  @doc """
  Set a global value, ttl is in number of hours
  For global keys, we expect relatively short ttls
  """
  @spec put_global(any, any, non_neg_integer) :: {:ok | :error, boolean()}
  def put_global(key, value, ttl),
    do: Cachex.put(@cache_bucket, {:global, key}, value, ttl: :timer.hours(ttl))

  @doc """
  Retrieve a global value from the cache global scope
  """
  @spec get_global(any()) :: {:ok | :error, any()}
  def get_global(key),
    do: Cachex.get(@cache_bucket, {:global, key})
end
