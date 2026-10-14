defmodule Glific.Http.FinchAdapter do
  @moduledoc """
  Tesla adapter that sends requests through Finch and returns network failures as plain
  reasons (`{:error, :timeout}`, `{:error, :econnrefused}`, `{:error, :checkout_timeout}`, ...),
  so callers and retry middleware can match on the reason without knowing the HTTP client.
  """
  @behaviour Tesla.Adapter

  alias Tesla.Adapter.Finch, as: TeslaFinch

  @pool_exhausted_message "Finch was unable to provide a connection"

  @doc """
  Runs the request through `Tesla.Adapter.Finch` and unwraps Finch/Mint error structs.
  """
  @impl Tesla.Adapter
  @spec call(Tesla.Env.t(), keyword()) :: Tesla.Env.result()
  def call(env, opts) do
    env
    |> TeslaFinch.call(opts)
    |> unwrap_error()
  rescue
    # Finch raises instead of returning an error when no pooled connection frees up in time
    error in RuntimeError ->
      if String.starts_with?(error.message, @pool_exhausted_message),
        do: {:error, :checkout_timeout},
        else: reraise(error, __STACKTRACE__)
  end

  @spec unwrap_error(Tesla.Env.result()) :: Tesla.Env.result()
  defp unwrap_error({:error, %Finch.TransportError{reason: reason}}), do: {:error, reason}
  defp unwrap_error({:error, %Finch.HTTPError{reason: reason}}), do: {:error, reason}
  defp unwrap_error({:error, %Finch.Error{reason: reason}}), do: {:error, reason}
  defp unwrap_error({:error, %Mint.HTTPError{reason: reason}}), do: {:error, reason}
  defp unwrap_error(result), do: result
end
