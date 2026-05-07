defmodule GlificWeb.Resolvers.AIEvaluations do
  @moduledoc """
  Resolvers for AI Evaluations
  """
  require Logger

  alias Glific.{
    AIEvaluations,
    AIEvaluations.AIEvaluation,
    AIEvaluations.GoldenQA,
    Assistants.AssistantConfigVersion,
    Metrics,
    Repo,
    ThirdParty.Kaapi
  }

  # 1MB
  @max_golden_qa_file_size 1 * 1024 * 1024
  @create_golden_qa_success_metric "Golden QA Create Success"
  @create_golden_qa_failure_metric "Golden QA Create Failure"

  @doc """
  List AI evaluations from the database.
  """
  @spec list_ai_evaluations(map(), map(), map()) :: {:ok, [AIEvaluation.t()]}
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
  List golden QAs from the database.
  """
  @spec list_golden_qas(map(), map(), map()) :: {:ok, [GoldenQA.t()]}
  def list_golden_qas(_, args, %{context: %{current_user: user}}) do
    args = Map.put(args, :organization_id, user.organization_id)
    {:ok, AIEvaluations.list_golden_qas(args)}
  end

  @doc """
  Count golden QAs from the database.
  """
  @spec count_golden_qas(map(), map(), map()) :: {:ok, non_neg_integer()}
  def count_golden_qas(_, args, %{context: %{current_user: user}}) do
    args = Map.put(args, :organization_id, user.organization_id)
    {:ok, AIEvaluations.count_golden_qas(args)}
  end

  @doc """
  Create a Golden QA configuration after validating the input.
  """
  @spec create_golden_qa(map(), map(), map()) ::
          {:ok, %{golden_qa: GoldenQA.t()} | %{errors: [%{message: String.t()}]}}
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
         {:ok, kaapi_dataset} <- Kaapi.upload_evaluation_dataset(dataset, user.organization_id) do
      create_golden_qa_record(kaapi_dataset, name, file, factor, user)
    else
      {:error, :timeout} ->
        {:ok, %{errors: [%{message: "Timeout occurred, please try again."}]}}

      {:error, %{status: _, body: %{:error => error}}} ->
        {:ok, %{errors: [%{message: error}]}}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = format_changeset_errors(changeset)
        Logger.error("Failed to save golden QA to database: #{inspect(errors)}")
        {:ok, %{errors: errors}}

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

  @spec create_golden_qa_record(map(), String.t(), Plug.Upload.t(), integer(), map()) ::
          {:ok, %{golden_qa: GoldenQA.t()}} | {:ok, %{errors: [%{message: String.t()}]}}
  defp create_golden_qa_record(kaapi_dataset, name, file, factor, user) do
    case AIEvaluations.create_golden_qa(%{
           name: name,
           dataset_id: kaapi_dataset.dataset_id,
           duplication_factor: factor,
           file_name: file.filename,
           organization_id: user.organization_id
         }) do
      {:ok, golden_qa} ->
        {:ok, %{golden_qa: golden_qa}}

      {:error, %Ecto.Changeset{} = changeset} ->
        cleanup_orphaned_kaapi_dataset(kaapi_dataset.dataset_id, user.organization_id)
        errors = format_changeset_errors(changeset)
        Logger.error("Failed to save golden QA to database: #{inspect(errors)}")
        {:ok, %{errors: errors}}
    end
  end

  @spec cleanup_orphaned_kaapi_dataset(non_neg_integer() | String.t(), non_neg_integer()) :: :ok
  defp cleanup_orphaned_kaapi_dataset(dataset_id, organization_id) do
    case Kaapi.delete_evaluation_dataset(dataset_id, organization_id) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Glific.log_exception(%Kaapi.Error{
          message: "Failed to delete orphaned Kaapi dataset",
          organization_id: organization_id,
          reason: inspect(reason)
        })

        # Returning ok as we don't want to block the main flow
        :ok
    end
  end

  @spec format_changeset_errors(Ecto.Changeset.t()) :: [%{message: String.t()}]
  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, messages} ->
      %{message: "#{field}: #{Enum.join(messages, "; ")}"}
    end)
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
  Get Golden QA dataset details with optional signed URL.
  Only fetches from Kaapi if include_signed_url is true to minimize network hops.
  """
  @spec get_golden_qa(map(), map(), map()) ::
          {:ok, %{golden_qa: map()} | %{errors: [%{message: String.t()}]}}
  def get_golden_qa(_, %{id: golden_qa_id, include_signed_url: include_signed_url}, %{
        context: %{current_user: user}
      }) do
    with {:ok, golden_qa} <- Repo.fetch(Glific.AIEvaluations.GoldenQA, golden_qa_id),
         {:ok, kaapi_data} <- fetch_kaapi_dataset(golden_qa, user, include_signed_url) do
      golden_qa_map =
        %{
          id: golden_qa.id,
          name: golden_qa.name,
          duplication_factor: golden_qa.duplication_factor,
          file_name: golden_qa.file_name,
          inserted_at: golden_qa.inserted_at,
          updated_at: golden_qa.updated_at
        }
        |> maybe_put_signed_url(kaapi_data)

      {:ok, %{golden_qa: golden_qa_map}}
    else
      {:error, [_, "Resource not found"]} ->
        {:ok, %{errors: [%{message: "Golden QA not found."}]}}

      {:error, error} when is_binary(error) ->
        {:ok, %{errors: [%{message: error}]}}

      {:error, _} ->
        {:ok,
         %{errors: [%{message: "An unknown error occurred, please contact Glific support."}]}}
    end
  end

  @spec maybe_put_signed_url(map(), map()) :: map()
  defp maybe_put_signed_url(golden_qa_map, %{} = kaapi_data) do
    case Map.get(kaapi_data, :signed_url) do
      nil -> golden_qa_map
      signed_url -> Map.put(golden_qa_map, :signed_url, signed_url)
    end
  end

  @spec fetch_kaapi_dataset(map(), map(), boolean()) ::
          {:ok, map()} | {:error, String.t()}
  defp fetch_kaapi_dataset(_golden_qa, _user, false), do: {:ok, %{}}

  defp fetch_kaapi_dataset(golden_qa, user, true) do
    case Kaapi.get_dataset(golden_qa.dataset_id, user.organization_id, true) do
      {:ok, %{signed_url: signed_url}} ->
        {:ok, %{signed_url: signed_url}}

      {:error, :timeout} ->
        {:error, "Timeout occurred, please try again."}

      {:error, %{status: _, body: %{error: error}}} ->
        {:error, error}

      {:error, msg} when is_binary(msg) ->
        {:error, msg}

      {:error, _} ->
        {:error, "An unknown error occurred, please contact Glific support."}
    end
  end

  @doc """
  Fetch evaluation scores for a given AI evaluation from Kaapi.
  """
  @spec get_evaluation_scores(map(), map(), map()) ::
          {:ok, %{scores: map()} | %{errors: [%{message: String.t()}]}}
  def get_evaluation_scores(_, %{id: evaluation_id}, %{context: %{current_user: user}}) do
    case AIEvaluations.get_evaluation_scores(evaluation_id, user.organization_id) do
      {:ok, %{data: data}} ->
        {:ok, %{scores: data}}

      {:error, :timeout} ->
        {:ok, %{errors: [%{message: "Timeout occurred, please try again."}]}}

      {:error, [_, "Resource not found"]} ->
        {:ok, %{errors: [%{message: "Evaluation not found."}]}}

      {:error, msg} when is_binary(msg) ->
        {:ok, %{errors: [%{message: msg}]}}

      {:error, _} ->
        {:ok,
         %{errors: [%{message: "An unknown error occurred, please contact Glific support."}]}}
    end
  end

  @doc """
  Create an AI Evaluation by sending the input to Kaapi, storing the result in the DB,
  and returning the evaluation.
  """
  @spec create_evaluation(map(), map(), map()) :: {:ok, map()} | {:error, String.t()}
  def create_evaluation(_, %{input: input}, %{context: %{current_user: user}}) do
    with {:ok, config_version} <-
           Repo.fetch_by(AssistantConfigVersion, %{id: input.config_version}),
         {:golden_qa, {:ok, golden_qa}} <-
           {:golden_qa,
            Repo.fetch_by(GoldenQA, %{
              id: input.golden_qa_id,
              organization_id: user.organization_id
            })},
         kaapi_input =
           input
           |> Map.put(:config_version, config_version.kaapi_version_number)
           |> Map.put(:dataset_id, golden_qa.dataset_id)
           |> Map.delete(:golden_qa_id),
         {:ok, %{data: data}} <- Kaapi.create_evaluation(kaapi_input, user.organization_id),
         {:ok, evaluation} <-
           AIEvaluations.create_ai_evaluation(%{
             name: input.experiment_name,
             status: String.to_existing_atom(data.status),
             kaapi_evaluation_id: data.id,
             golden_qa_id: input.golden_qa_id,
             assistant_config_version_id: input.config_version,
             organization_id: user.organization_id
           }) do
      {:ok, %{evaluation: evaluation}}
    else
      {:golden_qa, {:error, _}} ->
        {:error,
         "The specified Golden QA dataset does not exist or does not belong to your organization."}

      {:error, :timeout} ->
        {:error, "Timeout occurred, please try again."}

      {:error, %{body: %{:error => error}}} ->
        {:error, error}

      {:error, msg} when is_binary(msg) ->
        {:error, msg}

      {:error, [_, "Resource not found"]} ->
        {:error, "The specified config version does not exist."}

      {:error, _} ->
        {:error, "An unknown error occurred, please contact Glific support."}
    end
  end
end
