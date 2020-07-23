defmodule Glific.Cache do
  @moduledoc """
    Glific Cache management
  """

  @doc """
  Store all the in cachex :flows_cache. At some point, we will just use this dynamically
  """

  @spec set(list(), ( any() -> any()), map()) :: {:ok, any()}
  def set(keys, process_fn, args), do: set_to_cache(keys, process_fn.(args))

  def set(keys, value) when is_list(keys), do: set_to_cache(keys, value)

  def set(key, value), do: set_to_cache([key], value)


  @spec set_to_cache(list(), any) :: {:ok, any()}
  defp set_to_cache(keys, value) do
    keys = Enum.reduce(keys, [], fn key, acc -> [{key, value} | acc] end)
    Cachex.put_many(:flows_cache, keys)
    {:ok, value}
  end

  @spec get(any()) :: any()
  def get(key) do
    with {:ok, true} <- Cachex.exists?(:flows_cache, key),
         do: Cachex.get(:flows_cache, key)
  end

  @spec get_or_update(any, any, any) :: {atom, any}
  def get_or_update(key, process_fn, args) do
    with {:ok, true} <- Cachex.exists?(:flows_cache, key) do
      Cachex.get(:flows_cache, key)
    else
      _ -> set([key], process_fn, args)
    end
  end

  @spec remove(list()) :: any()
  def remove(keys),
    do: Enum.reduce(keys, fn key, _acc -> Cachex.del(:my_cache, key) end)
end
