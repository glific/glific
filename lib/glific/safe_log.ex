defmodule Glific.SafeLog do
  @moduledoc """
  Safe logging helpers that prevent credentials and sensitive runtime state
  from being written to logs.

  ## Why value-based, not path-based

  Filtering by field path ("strip :authorization from headers") breaks the
  moment a library renames a field or nests a struct differently. Instead,
  this module targets *types* of values that are always unsafe to log,
  regardless of where they appear in a data structure.

  The primary target is `%Tesla.Env{}`: its `__client__` field holds the
  middleware chain, which includes `Tesla.Middleware.Headers` pre-processors
  that carry live `Authorization: Bearer …` tokens. Stripping that one field
  is sufficient to make any Tesla response safe to inspect.

  ## Usage

      # In any module that logs Tesla errors:
      alias Glific.SafeLog

      {:error, env} -> Logger.warning("API failed: \#{SafeLog.safe_inspect(env)}")
  """

  require Logger

  @doc """
  Like `inspect/1` but strips the `__client__` field from any `%Tesla.Env{}`
  before formatting, so OAuth tokens in middleware headers are never logged.

  All other terms pass through unchanged.

  ## Examples

      iex> SafeLog.safe_inspect("plain string")
      ~s("plain string")

      iex> env = %Tesla.Env{status: 429, __client__: %Tesla.Client{}}
      iex> SafeLog.safe_inspect(env) =~ "429"
      true
      iex> SafeLog.safe_inspect(env) =~ "Bearer"
      false

  """
  @spec safe_inspect(term()) :: String.t()
  def safe_inspect(%Tesla.Env{} = env), do: inspect(%{env | __client__: nil})
  def safe_inspect(term), do: inspect(term)
end
