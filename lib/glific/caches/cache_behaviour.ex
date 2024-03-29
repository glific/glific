defmodule Glific.Caches.CacheBehaviour do
  @moduledoc """
  The cache API behaviour
  """

  @callback set(non_neg_integer, list(), any(), Keyword.t()) :: {:ok, any()}

  @callback set(non_neg_integer, String.t() | atom(), any(), Keyword.t()) :: {:ok, any()}

  @callback get(non_neg_integer, String.t() | atom()) :: {:ok, any()} | {:ok, false}

  @callback fetch(non_neg_integer, String.t() | atom(), (any() -> any())) ::
              {:ok | :error | :commit | :ignore, any()}

  @callback remove(non_neg_integer, list()) :: any()
end
