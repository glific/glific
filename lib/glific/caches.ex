defmodule Glific.Caches do
  @moduledoc """
    Glific Cache management
  """

  @doc """
  Store all the in cachex :flows_cache. At some point, we will just use this dynamically
  """
  @spec set(list(), (any() -> any()), map()) :: {:ok, any()}
  def set(keys, process_fn, args), do: set_to_cache(keys, process_fn.(args))

  @doc false
  @spec set(list(), any()) :: {:ok, any()}
  def set(keys, value) when is_list(keys), do: set_to_cache(keys, value)

  @doc false
  @spec set(String.t() | atom(), any()) :: {:ok, any()}
  def set(key, value), do: set_to_cache([key], value)

  @doc false
  @spec set_to_cache(list(), any) :: {:ok, any()}
  defp set_to_cache(keys, value) do
    keys = Enum.reduce(keys, [], fn key, acc -> [{key, value} | acc] end)
    Cachex.put_many(:flows_cache, keys)
    {:ok, value}
  end

  @doc """
  Get a cached value based on a key
  """
  @spec get(any()) :: {:ok, any()}
  def get(key) do
    with {:ok, true} <- Cachex.exists?(:flows_cache, key),
         do: Cachex.get(:flows_cache, key)
  end

  @doc """
  Get a cached value based on a key and if that now exists add that into the cache
  """
  @spec get_or_create(atom(), any, map()) :: {atom(), any}
  def get_or_create(key, process_fn, args) do
    case Cachex.exists?(:flows_cache, key) do
      {:ok, true} -> Cachex.get(:flows_cache, key)
      _ -> set([key], process_fn, args)
    end
  end

  @doc """
  Remove a value from the cache
  """
  @spec remove(list()) :: any()
  def remove(keys),
    do: Enum.reduce(keys, fn key, _acc -> Cachex.del(:my_cache, key) end)
end
