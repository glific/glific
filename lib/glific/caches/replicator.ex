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
  def replicate(operation),
    do: Phoenix.PubSub.broadcast(Glific.PubSub, @topic, {__MODULE__, node(), operation})

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
  defp apply_operation({:put_many, entries, opts}),
    do: Cachex.put_many(@cache_bucket, entries, opts)

  defp apply_operation({:delete, cache_keys}),
    do: Enum.each(cache_keys, &Cachex.del(@cache_bucket, &1))
end
