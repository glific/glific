defmodule Glific.AI.Models do
  @moduledoc """
  Which provider and model Glific AI uses, read from application config.

  No other module names a model, so switching one is a config change.
  """

  @default_max_tokens 4_096
  @default_receive_timeout 60_000

  @doc """
  The configured model spec, in the provider's `"provider:model"` form.
  """
  @spec spec() :: String.t() | nil
  def spec, do: config()[:model]

  @doc "Per-call options derived from configuration."
  @spec opts() :: keyword()
  def opts do
    [
      max_tokens: config()[:max_tokens] || @default_max_tokens,
      receive_timeout: config()[:receive_timeout] || @default_receive_timeout
    ]
  end

  @doc """
  Whether a model has been configured at all. A missing model is a
  misconfiguration to report, not a reason to fail at boot.
  """
  @spec configured?() :: boolean()
  def configured? do
    case spec() do
      spec when is_binary(spec) -> spec != ""
      _ -> false
    end
  end

  @spec config() :: keyword()
  defp config, do: Application.get_env(:glific, Glific.AI, [])
end
