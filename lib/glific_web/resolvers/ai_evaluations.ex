defmodule GlificWeb.Resolvers.AIEvaluations do
  @moduledoc """
  Resolvers for AI Evaluations
  """
  require Logger

  alias Glific.{AIEvaluations, Metrics, ThirdParty.Kaapi}

  # 1MB
  @max_golden_qa_file_size 1 * 1024 * 1024
  @create_golden_qa_success_metric "Golden QA Create Success"
  @create_golden_qa_failure_metric "Golden QA Create Failure"

  @doc """
  List AI evaluations from the database.
  """
  @spec list_ai_evaluations(map(), map(), map()) :: {:ok, list()}
  def list_ai_evaluations(_, args, %{context: %{current_user: user}}) do
    args = Map.put(args, :organization_id, user.organization_id)
    {:ok, AIEvaluations.list_ai_evaluations(args)}
  end

  @doc """
  Count AI evaluations from the database.
  """
  @spec count_ai_evaluations(map(), map(), map()) :: {:ok, non_neg_integer()}
  def count_ai_evaluations(_, args, %{context: %{current_user: user}}) do
    args = Map.put(args, :organization_id, user.organization_id)
    {:ok, AIEvaluations.count_ai_evaluations(args)}
  end

  @doc """
  Create a Golden QA configuration after validating the input.
  """
  @spec create_golden_qa(map(), map(), map()) :: {:ok, map()}
  def create_golden_qa(_, %{input: %{name: name, file: file, duplication_factor: factor}}, %{
        context: %{current_user: user}
      }) do
    dataset = %{
      dataset_name: name,
      file: file,
      duplication_factor: factor
    }

    with :ok <- validate_golden_qa_name(name),
         :ok <- validate_duplication_factor(factor),
         :ok <- validate_golden_qa_file_size(file, user),
         {:ok, res} <- Kaapi.upload_evaluation_dataset(dataset, user.organization_id) do
      {:ok, %{golden_qa: res}}
    else
      {:error, :timeout} ->
        {:ok, %{errors: [%{message: "Timeout occurred, please try again."}]}}

      {:error, %{status: _, body: %{:error => error}}} ->
        {:ok, %{errors: [%{message: error}]}}

      {:error, msg} when is_binary(msg) ->
        {:ok, %{errors: [%{message: msg}]}}

      {:error, _err} ->
        {:ok,
         %{errors: [%{message: "An unknown error occurred, please contact Glific support."}]}}
    end
    |> case do
      {:ok, %{errors: _} = data} ->
        Metrics.increment(@create_golden_qa_failure_metric, user.organization_id)
        {:ok, data}

      {:ok, data} ->
        Metrics.increment(@create_golden_qa_success_metric, user.organization_id)
        {:ok, data}
    end
  end

  @spec validate_golden_qa_name(String.t()) :: :ok | {:error, String.t()}
  defp validate_golden_qa_name(name) do
    if Regex.match?(~r/^[a-z0-9_]+$/, name) do
      :ok
    else
      {:error, "Name can only contain lowercase alphanumeric characters and underscores"}
    end
  end

  @spec validate_duplication_factor(integer()) :: :ok | {:error, String.t()}
  defp validate_duplication_factor(factor) when factor in 1..5, do: :ok

  defp validate_duplication_factor(_factor),
    do: {:error, "Duplication factor must be between 1 and 5"}

  @spec validate_golden_qa_file_size(struct(), map()) :: :ok | {:error, String.t()}
  defp validate_golden_qa_file_size(%{path: path}, %{id: id, organization_id: organization_id}) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @max_golden_qa_file_size ->
        :ok

      {:ok, %{size: _size}} ->
        {:error, "File size must not exceed 1MB"}

      {:error, reason} ->
        Logger.error(
          "Create Golden QA: User ID: #{id}: Org ID: #{organization_id}: Unable to read uploaded file for size validation due to #{inspect(reason)}"
        )

        {:error, "Unable to read uploaded file for size validation"}
    end
  end

  @doc """
  Create an AI Evaluation by sending the input to Kaapi, storing the result in the DB,
  and returning the evaluation.
  """
  @spec create_evaluation(map(), map(), map()) :: {:ok, map()}
  def create_evaluation(_, %{input: input}, %{context: %{current_user: user}}) do
    with {:ok, %{data: data}} <- Kaapi.create_evaluation(input, user.organization_id),
         {:ok, evaluation} <-
           AIEvaluations.create_ai_evaluation(%{
             name: input.experiment_name,
             status: String.to_existing_atom(data.status),
             kaapi_evaluation_id: data.id,
             dataset_id: data.dataset_id,
             assistant_config_version_id: input.config_version,
             organization_id: user.organization_id
           }) do
      {:ok, %{evaluation: evaluation}}
    else
      {:error, :timeout} ->
        {:error, "Timeout occurred, please try again."}

      {:error, %{body: %{:error => error}}} ->
        {:error, error}

      {:error, msg} when is_binary(msg) ->
        {:error, msg}

      {:error, _} ->
        {:error, "An unknown error occurred, please contact Glific support."}
    end
  end
end
