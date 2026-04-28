defmodule Glific.AIEvaluations do
  @moduledoc """
  Context module for AI Evaluations stored in the database.
  """
  import Ecto.Query

  require Logger

  alias Glific.{
    AIEvaluations.AIEvaluation,
    Repo,
    ThirdParty.Kaapi
  }

  @timeout_hours 1

  @doc """
  Returns the list of AI evaluations for an organization.

  ## Examples

      iex> list_ai_evaluations(%{organization_id: 1})
      [%AIEvaluation{}, ...]

  """
  @spec list_ai_evaluations(map()) :: [AIEvaluation.t()]
  def list_ai_evaluations(args) do
    args
    |> Repo.list_filter_query(AIEvaluation, &Repo.opts_with_inserted_at/2, &filter_with/2)
    |> Repo.all()
  end

  @doc """
  Returns the count of AI evaluations for an organization.
  """
  @spec count_ai_evaluations(map()) :: non_neg_integer()
  def count_ai_evaluations(args),
    do: Repo.count_filter(args, AIEvaluation, &filter_with/2)

  @doc """
  Creates an AI evaluation record in the database from a Kaapi response.
  """
  @spec create_ai_evaluation(map()) :: {:ok, AIEvaluation.t()} | {:error, Ecto.Changeset.t()}
  def create_ai_evaluation(attrs) do
    %AIEvaluation{}
    |> AIEvaluation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing AI evaluation record.
  """
  @spec update_ai_evaluation(AIEvaluation.t(), map()) ::
          {:ok, AIEvaluation.t()} | {:error, Ecto.Changeset.t()}
  def update_ai_evaluation(evaluation, attrs) do
    evaluation
    |> AIEvaluation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Polls Kaapi for status of processing evaluations and times out stale ones.
  Called once per minute by the cron job for each organization.
  """
  @spec poll_and_update(non_neg_integer()) :: :ok
  def poll_and_update(org_id) do
    timeout_threshold = DateTime.utc_now() |> DateTime.add(-@timeout_hours, :hour)

    AIEvaluation
    |> where([e], e.status in [:processing])
    |> where([e], e.inserted_at < ^timeout_threshold)
    |> Repo.all()
    |> Enum.each(fn evaluation ->
      Logger.warning("Timing out AI evaluation #{evaluation.id} for org #{org_id}")
      update_ai_evaluation(evaluation, %{status: :failed, failure_reason: "Evaluation timed out"})
    end)

    AIEvaluation
    |> where([e], e.status == :processing)
    |> where([e], e.inserted_at >= ^timeout_threshold)
    |> Repo.all()
    |> Enum.each(&poll_evaluation(&1, org_id))

    :ok
  end

  @spec poll_evaluation(AIEvaluation.t(), non_neg_integer()) :: :ok
  defp poll_evaluation(%AIEvaluation{} = evaluation, org_id) do
    case Kaapi.get_evaluation(evaluation.kaapi_evaluation_id, org_id) do
      {:ok, %{data: %{status: "completed"}}} ->
        results =
          case Kaapi.get_evaluation_scores(evaluation.kaapi_evaluation_id, org_id) do
            {:ok, %{data: data}} ->
              Map.get(data, :score, %{})

            {:error, reason} ->
              Logger.error(
                "Failed to fetch scores for AI evaluation #{evaluation.id}: #{inspect(reason)}"
              )

              %{}
          end

        update_ai_evaluation(evaluation, %{status: :completed, results: results})

      {:ok, %{data: %{status: "failed"} = data}} ->
        update_ai_evaluation(evaluation, %{
          status: :failed,
          failure_reason: Map.get(data, :failure_reason, "Evaluation failed")
        })

      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to poll AI evaluation #{evaluation.id} for org #{org_id}: #{inspect(reason)}"
        )

        :ok
    end
  end

  @spec filter_with(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_with(query, filter) do
    Enum.reduce(filter, query, fn
      {:name, name}, query ->
        where(query, [e], ilike(e.name, ^"%#{name}%"))
    end)
  end
end
