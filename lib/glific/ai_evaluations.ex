defmodule Glific.AIEvaluations do
  @moduledoc """
  Context module for AI Evaluations stored in the database.
  """
  import Ecto.Query
  import Glific.SafeLog

  require Logger

  alias Ecto.Multi

  alias Glific.{
    AIEvaluations.AIEvaluation,
    AIEvaluations.GoldenQA,
    AIEvaluations.OrganizationEvalRequest,
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Assistants.KnowledgeBaseVersion,
    Metrics,
    Notifications,
    Partners,
    Repo,
    ThirdParty.Kaapi
  }

  alias Glific.ThirdParty.Discord.Notifications, as: DiscordNotifications

  @tunable_settings_keys ~w(temperature effort)

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
  Polls Kaapi for status of processing evaluations.
  Called once per minute by the cron job for each organization.
  """
  @spec poll_and_update(non_neg_integer()) :: :ok
  def poll_and_update(org_id) do
    AIEvaluation
    |> where([e], e.status == :processing)
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

    case do_update(evaluation, %{status: :completed, results: %{summary_scores: summary_scores}}) do
      {:ok, updated_evaluation} ->
        duration_seconds = DateTime.diff(DateTime.utc_now(), evaluation.inserted_at)

        Appsignal.add_distribution_value("ai_evaluation_duration", duration_seconds, %{
          org_id: org_id
        })

        Metrics.increment("AI Evaluation Completed", org_id)

        Notifications.create_notification(%{
          category: "AI Evaluation",
          message: "AI evaluation #{updated_evaluation.name} completed successfully.",
          severity: Notifications.types().info,
          organization_id: org_id,
          entity: %{evaluation_id: updated_evaluation.id}
        })

        :ok

      _ ->
        :ok
    end
  end

  defp handle_evaluation_status({:ok, %{data: %{status: "failed"} = data}}, evaluation, org_id) do
    failure_reason = Map.get(data, :error_message, "Evaluation failed")

    case do_update(evaluation, %{status: :failed, failure_reason: failure_reason}) do
      {:ok, updated_evaluation} ->
        Metrics.increment("AI Evaluation Failed", org_id)

        Notifications.create_notification(%{
          category: "AI Evaluation",
          message: "AI evaluation #{updated_evaluation.name} failed: #{failure_reason}",
          severity: Notifications.types().warning,
          organization_id: org_id,
          entity: %{evaluation_id: updated_evaluation.id}
        })

        :ok

      _ ->
        :ok
    end
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

  # Atomically transitions from :processing so a racing cron poll and Kaapi callback can't
  # both apply side effects (notifications, metrics, subscription publish) for the same row.
  @spec do_update(AIEvaluation.t(), map()) ::
          {:ok, AIEvaluation.t()} | :noop | {:error, Ecto.Changeset.t()}
  defp do_update(evaluation, attrs) do
    changeset = AIEvaluation.changeset(evaluation, attrs)

    if changeset.valid? do
      set = Keyword.new(changeset.changes) ++ [updated_at: DateTime.utc_now(:second)]

      AIEvaluation
      |> where([e], e.id == ^evaluation.id and e.status == :processing)
      |> select([e], e)
      |> Repo.update_all([set: set], returning: true)
      |> case do
        {1, [updated_evaluation]} ->
          Absinthe.Subscription.publish(
            GlificWeb.Endpoint,
            updated_evaluation,
            ai_evaluation_updated: "#{updated_evaluation.organization_id}"
          )

          {:ok, updated_evaluation}

        {0, _} ->
          :noop
      end
    else
      {:error, changeset}
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

  @doc """
  Requests access to the AI Evaluations feature for an organization.
  Idempotent: if a request already exists for the org, returns the existing one.
  """
  @spec request_eval_access(non_neg_integer()) ::
          {:ok, OrganizationEvalRequest.t()} | {:error, Ecto.Changeset.t()}
  def request_eval_access(organization_id) do
    case Repo.fetch_by(OrganizationEvalRequest, %{organization_id: organization_id}) do
      {:ok, existing} ->
        {:ok, existing}

      {:error, _} ->
        result =
          %OrganizationEvalRequest{}
          |> OrganizationEvalRequest.changeset(%{organization_id: organization_id})
          |> Repo.insert()

        with {:ok, _} <- result do
          organization_id
          |> Partners.organization()
          |> DiscordNotifications.send_eval_access_request()
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

  @doc """
  Dispatches a v2 (native-judge) prompt improvement request to Kaapi for a completed evaluation.
  """
  @spec request_improve_prompt(non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, any()}
  def request_improve_prompt(evaluation_id, organization_id) do
    with {:ok, evaluation} <-
           Repo.fetch_by(AIEvaluation, %{id: evaluation_id, organization_id: organization_id}),
         {:status, :completed} <- {:status, evaluation.status},
         callback_url = build_improve_prompt_callback_url(organization_id),
         {:ok, _} <-
           Kaapi.improve_evaluation_prompt(
             evaluation.kaapi_evaluation_id,
             callback_url,
             organization_id
           ) do
      {:ok, %{status: "pending"}}
    else
      {:status, status} ->
        {:error,
         "Evaluation is #{status}, must be completed before requesting prompt improvement."}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Handles the async callback POSTed by Kaapi after v2 prompt-improvement completes.
  """
  @spec handle_improve_prompt_callback(map()) ::
          {:ok, AssistantConfigVersion.t() | :acknowledged} | {:error, String.t()}
  def handle_improve_prompt_callback(%{"data" => %{"status" => "SUCCESS"} = data}),
    do: create_improve_prompt_config_version(data["config_version"] || %{})

  def handle_improve_prompt_callback(%{"data" => %{"status" => "FAILED"} = data}) do
    Glific.log_exception(%Kaapi.Error{
      message: "Improve prompt failed",
      reason: safe_inspect(data)
    })

    {:ok, :acknowledged}
  end

  # Non-terminal status (e.g. still PENDING) — nothing to do yet.
  def handle_improve_prompt_callback(%{"data" => %{"status" => _}}),
    do: {:ok, :acknowledged}

  # Defensive catch-all: the callback endpoint is public, so a malformed body must not
  # raise (the controller must still return 200).
  def handle_improve_prompt_callback(params) do
    Glific.log_exception(%Kaapi.Error{
      message: "Unexpected improve prompt callback payload",
      reason: safe_inspect(params)
    })

    {:error, "Unexpected improve prompt callback payload"}
  end

  @spec build_improve_prompt_callback_url(non_neg_integer()) :: String.t()
  defp build_improve_prompt_callback_url(organization_id) do
    organization = Partners.organization(organization_id)
    Glific.api_callback_base(organization.shortcode) <> "/kaapi/improve_prompt"
  end

  @doc """
  Handles Kaapi's async callback when a v2 evaluation run finishes (completed or failed).
  """
  @spec handle_evaluation_run_callback(map()) :: :ok
  def handle_evaluation_run_callback(%{
        "data" => %{"id" => kaapi_evaluation_id, "status" => status}
      })
      when status in ["completed", "failed"] do
    case Repo.fetch_by(AIEvaluation, %{kaapi_evaluation_id: kaapi_evaluation_id}) do
      {:ok, evaluation} ->
        poll_evaluation(evaluation, evaluation.organization_id)

      {:error, reason} ->
        Glific.log_exception(%Kaapi.Error{
          message:
            "Evaluation run callback for unknown kaapi_evaluation_id=#{kaapi_evaluation_id}",
          reason: safe_inspect(reason)
        })
    end

    :ok
  end

  # non-terminal status (e.g. PROCESSING) — nothing to do
  def handle_evaluation_run_callback(%{"data" => %{"status" => _}}), do: :ok

  def handle_evaluation_run_callback(params) do
    Glific.log_exception(%Kaapi.Error{
      message: "Unexpected evaluation run callback payload",
      reason: safe_inspect(params)
    })

    :ok
  end

  @spec create_improve_prompt_config_version(map()) ::
          {:ok, AssistantConfigVersion.t()} | {:error, any()}
  defp create_improve_prompt_config_version(config_version_data) do
    with {:ok, assistant} <-
           Repo.fetch_by(Assistant, %{kaapi_uuid: config_version_data["config_id"]}) do
      completion = get_in(config_version_data, ["config_blob", "completion"]) || %{}
      params = completion["params"] || %{}

      changeset =
        AssistantConfigVersion.changeset(%AssistantConfigVersion{}, %{
          assistant_id: assistant.id,
          organization_id: assistant.organization_id,
          prompt: params["instructions"],
          provider: completion["provider"] || "openai",
          model: params["model"],
          settings: extract_settings(params),
          status: :ready,
          kaapi_version_number: config_version_data["version"],
          description: config_version_data["commit_message"]
        })

      Multi.new()
      |> Multi.insert(:config_version, changeset)
      |> link_improve_prompt_knowledge_bases(
        params["knowledge_base_ids"],
        assistant.organization_id
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{config_version: config_version}} ->
          {:ok, config_version}

        {:error, :knowledge_base_version, reason, _changes} ->
          {:error, reason}

        {:error, _failed, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  # Classic models tune via temperature, reasoning models via effort — the two
  # don't overlap on one model
  @spec extract_settings(map()) :: map()
  defp extract_settings(params), do: Map.take(params, @tunable_settings_keys)

  @spec link_improve_prompt_knowledge_bases(Multi.t(), [String.t()] | nil, non_neg_integer()) ::
          Multi.t()
  defp link_improve_prompt_knowledge_bases(multi, llm_service_ids, organization_id) do
    case List.first(llm_service_ids || []) do
      nil ->
        multi

      llm_service_id ->
        do_link_improve_prompt_knowledge_base(multi, llm_service_id, organization_id)
    end
  end

  @spec do_link_improve_prompt_knowledge_base(Multi.t(), String.t(), non_neg_integer()) ::
          Multi.t()
  defp do_link_improve_prompt_knowledge_base(multi, llm_service_id, organization_id) do
    multi
    |> Multi.run(:knowledge_base_version, fn _repo, _changes ->
      case Repo.fetch_by(KnowledgeBaseVersion, llm_service_id: llm_service_id) do
        {:error, _} ->
          {:error, "No matching knowledge base found for llm_service_id=#{llm_service_id}"}

        {:ok, knowledge_base_version} ->
          {:ok, knowledge_base_version}
      end
    end)
    |> Multi.insert_all(
      :link_knowledge_base,
      "assistant_config_version_knowledge_base_versions",
      fn %{config_version: config_version, knowledge_base_version: knowledge_base_version} ->
        [
          %{
            assistant_config_version_id: config_version.id,
            knowledge_base_version_id: knowledge_base_version.id,
            organization_id: organization_id,
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          }
        ]
      end
    )
  end
end
