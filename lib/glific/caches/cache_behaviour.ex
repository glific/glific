defmodule Glific.Caches.CacheBehaviour do
  @moduledoc """
  The cache API behaviour
  """

  @callback set(list(), (any() -> any()), map()) :: {:ok, any()}

  @callback set(list(), any()) :: {:ok, any()}

  @callback set(String.t() | atom(), any()) :: {:ok, any()}

  @callback get(String.t() | atom()) :: {:ok, any()} | {:ok, false}

  @callback remove(list()) :: any()
end
