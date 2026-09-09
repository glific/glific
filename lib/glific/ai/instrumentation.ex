defmodule Glific.AI.Instrumentation do
  @moduledoc """
  Latency and outcome telemetry for AI provider calls.

  Kept out of the provider implementations so that adding a provider means
  writing the client and nothing else. `Glific.AI` wraps every call in
  `around/3`, the way the webhook dispatcher wraps `call/2`.
  """

  @count_metric "glific_ai_call_count"
  @latency_metric "glific_ai_call_latency"

  @doc "Wrap a provider `generate/2` with outcome count + latency telemetry."
  @spec around(module(), keyword(), (-> any())) :: any()
  def around(module, opts, fun) when is_atom(module) and is_function(fun, 0) do
    start = System.monotonic_time(:millisecond)
    result = fun.()

    record(module.model(opts) || "unknown", outcome(result), start)
    result
  end

  @spec outcome(any()) :: String.t()
  defp outcome({:ok, _reply, _usage}), do: "succeeded"
  defp outcome(_result), do: "failed"

  @spec record(String.t(), String.t(), integer()) :: :ok
  defp record(model, outcome, start) do
    tags = %{outcome: outcome, model: model}
    Appsignal.increment_counter(@count_metric, 1, tags)

    Appsignal.add_distribution_value(
      @latency_metric,
      System.monotonic_time(:millisecond) - start,
      tags
    )

    :ok
  end
end
