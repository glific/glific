defmodule Glific.AIEvaluations do
  @moduledoc """
  Context module for AI Evaluations stored in the database.
  """
  import Ecto.Query

  require Logger

  alias Glific.{
    AIEvaluations.AIEvaluation,
    AIEvaluations.GoldenQA,
    Metrics,
    Notifications,
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
    |> where([e], e.status == :processing)
    |> where([e], e.inserted_at < ^timeout_threshold)
    |> Repo.all()
    |> Enum.each(fn evaluation ->
      Logger.warning("Timing out AI evaluation #{evaluation.id} for org #{org_id}")
      Metrics.increment("AI Evaluation Timed Out", org_id)

      Notifications.create_notification(%{
        category: "AI Evaluation",
        message: "AI evaluation #{evaluation.name} timed out after #{@timeout_hours} hour(s).",
        severity: Notifications.types().warning,
        organization_id: org_id,
        entity: %{evaluation_id: evaluation.id}
      })

      do_update(evaluation, %{status: :failed, failure_reason: "Evaluation timed out"})
    end)

    AIEvaluation
    |> where([e], e.status == :processing)
    |> where([e], e.inserted_at >= ^timeout_threshold)
    |> Repo.all()
    |> Enum.each(fn evaluation ->
      poll_evaluation(evaluation, org_id)
      Process.sleep(100)
    end)

    :ok
  end

  @spec poll_evaluation(AIEvaluation.t(), non_neg_integer()) :: :ok
  defp poll_evaluation(%AIEvaluation{} = evaluation, org_id) do
    evaluation.kaapi_evaluation_id
    |> Kaapi.get_evaluation_scores(org_id)
    |> handle_evaluation_status(evaluation, org_id)
  end

  @spec handle_evaluation_status(tuple(), AIEvaluation.t(), non_neg_integer()) :: :ok
  defp handle_evaluation_status({:ok, %{data: %{status: "completed"} = data}}, evaluation, org_id) do
    summary_scores = data |> Map.get(:score, %{}) |> Map.get(:summary_scores, [])
    Metrics.increment("AI Evaluation Completed", org_id)

    Notifications.create_notification(%{
      category: "AI Evaluation",
      message: "AI evaluation #{evaluation.name} completed successfully.",
      severity: Notifications.types().info,
      organization_id: org_id,
      entity: %{evaluation_id: evaluation.id}
    })

    do_update(evaluation, %{status: :completed, results: %{summary_scores: summary_scores}})
  end

  defp handle_evaluation_status({:ok, %{data: %{status: "failed"} = data}}, evaluation, org_id) do
    failure_reason = Map.get(data, :error_message, "Evaluation failed")
    Metrics.increment("AI Evaluation Failed", org_id)

    Notifications.create_notification(%{
      category: "AI Evaluation",
      message: "AI evaluation #{evaluation.name} failed: #{failure_reason}",
      severity: Notifications.types().warning,
      organization_id: org_id,
      entity: %{evaluation_id: evaluation.id}
    })

    do_update(evaluation, %{status: :failed, failure_reason: failure_reason})
  end

  defp handle_evaluation_status({:ok, _}, _evaluation, _org_id), do: :ok

  defp handle_evaluation_status({:error, reason}, evaluation, org_id) do
    Logger.error(
      "Failed to poll AI evaluation #{evaluation.id} for org #{org_id}: #{inspect(reason)}"
    )

    :ok
  end

  @spec do_update(AIEvaluation.t(), map()) :: :ok
  defp do_update(evaluation, attrs) do
    case update_ai_evaluation(evaluation, attrs) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Logger.error(
          "Failed to update AI evaluation #{evaluation.id}: #{inspect(changeset.errors)}"
        )
    end
  end

  @doc """
  Returns the list of golden QAs for an organization.

  ## Examples

      iex> list_golden_qas(%{organization_id: 1})
      [%GoldenQA{}, ...]

  """
  @spec list_golden_qas(map()) :: [GoldenQA.t()]
  def list_golden_qas(args) do
    args
    |> Repo.list_filter_query(GoldenQA, &Repo.opts_with_inserted_at/2, &filter_golden_qas/2)
    |> Repo.all()
  end

  @doc """
  Returns the count of golden QAs for an organization.
  """
  @spec count_golden_qas(map()) :: non_neg_integer()
  def count_golden_qas(args),
    do: Repo.count_filter(args, GoldenQA, &filter_golden_qas/2)

  @doc """
  Creates a golden QA record in the database.
  """
  @spec create_golden_qa(map()) :: {:ok, GoldenQA.t()} | {:error, Ecto.Changeset.t()}
  def create_golden_qa(attrs) do
    %GoldenQA{}
    |> GoldenQA.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Fetches evaluation scores for a given AI evaluation from Kaapi.
  """
  @spec get_evaluation_scores(non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, any()}
  def get_evaluation_scores(evaluation_id, org_id) do
    with {:ok, %AIEvaluation{kaapi_evaluation_id: kaapi_id}} <-
           Repo.fetch(AIEvaluation, evaluation_id) do
      Kaapi.get_evaluation_scores(kaapi_id, org_id)
    end
  end

  @spec filter_with(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_with(query, filter) do
    Enum.reduce(filter, query, fn
      {:name, name}, query ->
        where(query, [e], ilike(e.name, ^"%#{name}%"))
    end)
  end

  @spec filter_golden_qas(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_golden_qas(query, filter) do
    Enum.reduce(filter, query, fn
      {:name, name}, query ->
        where(query, [g], ilike(g.name, ^"%#{name}%"))
    end)
  end
end
