defmodule Glific.AIEvaluations do
  @moduledoc """
  Context module for AI Evaluations stored in the database.
  """
  import Ecto.Query
  import Glific.SafeLog

  require Logger

  alias Glific.{
    AIEvaluations.AIEvaluation,
    AIEvaluations.GoldenQA,
    AIEvaluations.OrganizationEvalRequest,
    Mails.EvalAccessRequestMail,
    Metrics,
    Notifications,
    Partners,
    Repo,
    ThirdParty.Kaapi
  }

  @timeout_hours 6

  @doc """
  Returns the list of AI evaluations for an organization.

  ## Examples

      iex> list_ai_evaluations(%{organization_id: 1})
      [%AIEvaluation{}, ...]

  """
  @spec list_ai_evaluations(map()) :: [map()]
  def list_ai_evaluations(args) do
    args
    |> Repo.list_filter_query(AIEvaluation, &Repo.opts_with_inserted_at/2, &filter_with/2)
    |> Repo.all()
    |> Repo.preload([:golden_qa, assistant_config_version: :assistant])
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
    |> case do
      {:ok, evaluation} ->
        {:ok, evaluation}

      {:error, changeset} = result ->
        Logger.error(
          "Failed to create AI Evaluation record: name=#{attrs[:name]}, errors=#{safe_inspect(changeset.errors)}"
        )

        result
    end
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

    Logger.info(
      "AI Evaluation completed: id=#{evaluation.id}, name=#{evaluation.name}, " <>
        "org_id=#{org_id}, summary_scores_count=#{length(summary_scores)}, " <>
        "summary_scores=#{safe_inspect(summary_scores)}"
    )

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

    Logger.error(
      "AI Evaluation failed on Kaapi: id=#{evaluation.id}, name=#{evaluation.name}, " <>
        "org_id=#{org_id}, failure_reason=#{failure_reason}"
    )

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
    Glific.log_exception(%Glific.ThirdParty.Kaapi.Error{
      message:
        "Failed to poll AI Evaluation: id=#{evaluation.id}, name=#{evaluation.name}, " <>
          "org_id=#{org_id}",
      organization_id: org_id,
      reason: safe_inspect(reason)
    })

    :ok
  end

  @spec do_update(AIEvaluation.t(), map()) :: :ok
  defp do_update(evaluation, attrs) do
    case update_ai_evaluation(evaluation, attrs) do
      {:ok, updated} ->
        Logger.info(
          "AI Evaluation status updated: id=#{updated.id}, name=#{updated.name}, " <>
            "new_status=#{updated.status}"
        )

        :ok

      {:error, changeset} ->
        Glific.log_exception(%Glific.ThirdParty.Kaapi.Error{
          message:
            "Failed to update AI Evaluation record: id=#{evaluation.id}, name=#{evaluation.name}",
          organization_id: evaluation.organization_id,
          reason: safe_inspect(changeset.errors)
        })
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
    result =
      %GoldenQA{}
      |> GoldenQA.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, golden_qa} ->
        Logger.info(
          "Golden QA record created: id=#{golden_qa.id}, name=#{golden_qa.name}, " <>
            "dataset_id=#{golden_qa.dataset_id}, " <>
            "duplication_factor=#{golden_qa.duplication_factor}, " <>
            "file_name=#{golden_qa.file_name}, org_id=#{golden_qa.organization_id}"
        )

      {:error, changeset} ->
        Logger.error(
          "Failed to create Golden QA record: org_id=#{attrs[:organization_id]}, " <>
            "name=#{attrs[:name]}, errors=#{safe_inspect(changeset.errors)}"
        )
    end

    result
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

  @doc """
  Requests access to the AI Evaluations feature for an organization.
  Idempotent: if a request already exists for the org, returns the existing one.
  """
  @spec request_eval_access(non_neg_integer()) ::
          {:ok, OrganizationEvalRequest.t()} | {:error, Ecto.Changeset.t()}
  def request_eval_access(organization_id) do
    case Repo.fetch_by(OrganizationEvalRequest, %{organization_id: organization_id}) do
      {:ok, existing} ->
        Logger.info(
          "AI Evaluation access request already exists (idempotent): " <>
            "org_id=#{organization_id}, status=#{existing.status}"
        )

        {:ok, existing}

      {:error, _} ->
        result =
          %OrganizationEvalRequest{}
          |> OrganizationEvalRequest.changeset(%{organization_id: organization_id})
          |> Repo.insert()

        case result do
          {:ok, _request} ->
            Logger.info("New AI Evaluation access request created: org_id=#{organization_id}")

            Metrics.increment("AI Evaluation Access Requested", organization_id)

            organization_id
            |> Partners.organization()
            |> EvalAccessRequestMail.send_eval_access_request_mail()

          {:error, changeset} ->
            Logger.error(
              "Failed to create AI Evaluation access request: org_id=#{organization_id}, " <>
                "errors=#{safe_inspect(changeset.errors)}"
            )
        end

        result
    end
  end

  @doc """
  Returns the eval access request for an organization, or nil if none exists.
  """
  @spec get_eval_access_request(non_neg_integer()) ::
          {:ok, OrganizationEvalRequest.t()} | {:error, any()}
  def get_eval_access_request(organization_id),
    do: Repo.fetch_by(OrganizationEvalRequest, %{organization_id: organization_id})

  @spec filter_golden_qas(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_golden_qas(query, filter) do
    Enum.reduce(filter, query, fn
      {:name, name}, query ->
        where(query, [g], ilike(g.name, ^"%#{name}%"))
    end)
  end
end
