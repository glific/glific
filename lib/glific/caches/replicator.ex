defmodule Glific.Caches.Replicator do
  @moduledoc """
  Copies `Glific.Caches` writes to the other nodes of the cluster.

  Every node keeps its own Cachex, so without this a write on one node (publishing a flow on a web
  node, say) leaves the other nodes serving the old value until it expires. Writes are copied
  rather than turned into deletes so that a value fetched from an external API, such as a Gupshup
  token, is shared instead of each node wiping the other's and fetching a new one.
  """

  use GenServer

  @cache_bucket :glific_cache
  @topic "glific_cache"

  @type operation :: {:put_many, [{any(), any()}], Keyword.t()} | {:delete, [any()]}

  @doc false
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Sends a cache write made on this node to the other nodes
  """
  @spec replicate(operation()) :: :ok | {:error, term()}
  def replicate({:put_many, entries, opts}),
    do: broadcast({:put_many, entries, ttl_to_deadline(opts)})

  def replicate(operation), do: broadcast(operation)

  @spec broadcast(operation()) :: :ok | {:error, term()}
  defp broadcast(operation),
    do: Phoenix.PubSub.broadcast(Glific.PubSub, @topic, {__MODULE__, node(), operation})

  # A deadline rather than the ttl, so a copy that arrives late still expires when the original
  # does instead of outliving it (a cached token past its expiry, say).
  @spec ttl_to_deadline(Keyword.t()) :: Keyword.t()
  defp ttl_to_deadline(opts) do
    case Keyword.pop(opts, :ttl) do
      {ttl, opts} when is_integer(ttl) ->
        expires_at = System.system_time(:millisecond) + ttl
        Keyword.put(opts, :expires_at, expires_at)

      _ ->
        opts
    end
  end

  @impl true
  def init(nil) do
    :ok = Phoenix.PubSub.subscribe(Glific.PubSub, @topic)
    {:ok, nil}
  end

  @impl true
  def handle_info({__MODULE__, origin, _operation}, state) when origin == node(),
    do: {:noreply, state}

  def handle_info({__MODULE__, _origin, operation}, state) do
    apply_operation(operation)
    {:noreply, state}
  end

  @spec apply_operation(operation()) :: any()
  defp apply_operation({:put_many, entries, opts}) do
    case Keyword.pop(opts, :expires_at) do
      {nil, opts} ->
        Cachex.put_many(@cache_bucket, entries, opts)

      {expires_at, opts} ->
        remaining_ttl = expires_at - System.system_time(:millisecond)

        if remaining_ttl > 0,
          do: Cachex.put_many(@cache_bucket, entries, [{:ttl, remaining_ttl} | opts])
    end
  end

  defp apply_operation({:delete, cache_keys}),
    do: Enum.each(cache_keys, &Cachex.del(@cache_bucket, &1))
end
