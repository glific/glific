defmodule Glific.AI.Instrumentation do
  @moduledoc """
  Telemetry for Glific AI, at two granularities.

  `around/3` measures one provider call, and `Glific.AI` wraps every call in it.
  `question/1` measures answering a whole question, which is several calls, and
  is what alerting on Glific AI as a feature needs.

  Kept out of the provider implementations so that adding a provider means
  writing the client and nothing else.
  """

  @count_metric "glific_ai_call_count"
  @latency_metric "glific_ai_call_latency"

  @question_count_metric "glific_ai_question_count"
  @question_total_metric "glific_ai_question_total"
  @question_latency_metric "glific_ai_question_latency"
  @question_cost_metric "glific_ai_question_cost_micro_usd"
  @feedback_metric "glific_ai_feedback_count"

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

  @doc """
  Records one answered question: whether it succeeded, how long it took and
  what it cost, tagged by the skill that handled it.
  """
  @spec question(%{
          optional(any()) => any(),
          skill: String.t(),
          outcome: String.t(),
          duration_ms: non_neg_integer(),
          cost: number()
        }) :: :ok
  def question(%{skill: skill, outcome: outcome, duration_ms: duration_ms, cost: cost}) do
    tags = %{outcome: outcome, skill: skill}

    Appsignal.increment_counter(@question_count_metric, 1, tags)
    Appsignal.increment_counter(@question_total_metric, 1)
    Appsignal.add_distribution_value(@question_latency_metric, duration_ms, tags)
    Appsignal.add_distribution_value(@question_cost_metric, round(cost * 1_000_000), tags)

    :ok
  end

  @doc "Records a rating a person gave an answer."
  @spec feedback(String.t() | nil) :: :ok
  def feedback(rating) do
    Appsignal.increment_counter(@feedback_metric, 1, %{rating: rating || "unknown"})
    :ok
  end

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
