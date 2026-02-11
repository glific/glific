defmodule Glific.Assistants do
  @moduledoc """
  Context module for Assistant and related schemas
  """
  alias Ecto.Multi
  alias Glific.Assistants.Assistant
  alias Glific.Assistants.AssistantConfigVersion
  alias Glific.Assistants.KnowledgeBase
  alias Glific.Assistants.KnowledgeBaseVersion
  alias Glific.Repo
  alias Glific.ThirdParty.Kaapi

  require Logger

  @default_model "gpt-4o"

  @doc """
  Create a Knowledge Base.

  ## Examples

  iex> Glific.Assistants.create_knowledge_base(%{name: "Test KB", organization_id: 1})
  {:ok, %KnowledgeBase{name: "Test KB", organization_id: 1}}

  iex> Glific.Assistants.create_knowledge_base(%{name: "", organization_id: 1})
  {:error, %Ecto.Changeset{}}
  """
  @spec create_knowledge_base(map()) :: {:ok, KnowledgeBase.t()} | {:error, Ecto.Changeset.t()}
  def create_knowledge_base(attrs) do
    %KnowledgeBase{}
    |> KnowledgeBase.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Create a Knowledge Base Version.

  ## Examples

  iex> Glific.Assistants.create_knowledge_base_version(%{llm_service_id: "KB_VS_ID1", organization_id: 1, knowledge_base_id: 1, files: [%{"name" => "file1", "size" => 100}], status: :ready, size: 100})
  {:ok, %KnowledgeBaseVersion{name: "Test KB", organization_id: 1}}

  iex> Glific.Assistants.create_knowledge_base_version(%{llm_service_id: nil, organization_id: 1})
  {:error, %Ecto.Changeset{}}
  """
  @spec create_knowledge_base_version(map()) ::
          {:ok, KnowledgeBaseVersion.t()} | {:error, Ecto.Changeset.t()}
  def create_knowledge_base_version(attrs) do
    %KnowledgeBaseVersion{}
    |> KnowledgeBaseVersion.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an Assistant.
  """
  @spec create_assistant(map()) :: {:ok, map()} | {:error, any()}
  def create_assistant(user_params) do
    with :ok <- validate_knowledge_base_presence(user_params),
         {:ok, knowledge_base_version} <-
           KnowledgeBaseVersion.get_knowledge_base_version(user_params[:knowledge_base_id]),
         {:ok, kaapi_config} <- build_kaapi_config(user_params, knowledge_base_version),
         {:ok, kaapi_uuid} <- create_kaapi_assistant(kaapi_config, user_params[:organization_id]) do
      create_assistant_transaction(user_params, kaapi_config, kaapi_uuid, knowledge_base_version)
    end
  end

  @spec validate_knowledge_base_presence(map()) :: :ok | {:error, String.t()}
  defp validate_knowledge_base_presence(user_params) do
    if is_nil(user_params[:knowledge_base_id]) do
      {:error, "Knowledge base is required for assistant creation"}
    else
      :ok
    end
  end

  @spec build_kaapi_config(map(), KnowledgeBaseVersion.t()) :: {:ok, map()}
  defp build_kaapi_config(user_params, knowledge_base_version) do
    prompt = user_params[:instructions] || "You are a helpful assistant"

    config = %{
      temperature: user_params[:temperature] || 1,
      model: user_params[:model] || @default_model,
      organization_id: user_params[:organization_id],
      instructions: prompt,
      name: generate_temp_name(user_params[:name], "Assistant"),
      vector_store_ids: [knowledge_base_version.llm_service_id],
      prompt: prompt
    }

    {:ok, config}
  end

  @spec create_kaapi_assistant(map(), non_neg_integer()) :: {:ok, String.t()} | {:error, any()}
  defp create_kaapi_assistant(kaapi_config, organization_id) do
    case Kaapi.create_assistant_config(kaapi_config, organization_id) do
      {:ok, kaapi_response} when is_binary(kaapi_response.data.id) ->
        {:ok, kaapi_response.data.id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec create_assistant_transaction(map(), map(), String.t(), KnowledgeBaseVersion.t()) ::
          {:ok, map()} | {:error, any()}
  defp create_assistant_transaction(user_params, kaapi_config, kaapi_uuid, knowledge_base_version) do
    Multi.new()
    |> Multi.insert(:assistant, build_assistant_changeset(user_params, kaapi_config, kaapi_uuid))
    |> Multi.insert(
      :config_version,
      &build_config_version_changeset(&1, kaapi_config, knowledge_base_version)
    )
    |> Multi.update(:updated_assistant, &update_assistant_with_active_config/1)
    |> Multi.run(
      :link_knowledge_base,
      &link_knowledge_base_to_config(
        &1,
        &2,
        knowledge_base_version,
        user_params[:organization_id]
      )
    )
    |> Repo.transaction()
    |> handle_transaction_result()
  end

  @spec build_assistant_changeset(map(), map(), String.t()) :: Ecto.Changeset.t()
  defp build_assistant_changeset(user_params, kaapi_config, kaapi_uuid) do
    Assistant.changeset(%Assistant{}, %{
      name: kaapi_config.name,
      description: user_params[:description],
      kaapi_uuid: kaapi_uuid,
      organization_id: user_params[:organization_id]
    })
  end

  @spec build_config_version_changeset(map(), map(), KnowledgeBaseVersion.t()) ::
          Ecto.Changeset.t()
  defp build_config_version_changeset(
         %{assistant: assistant},
         kaapi_config,
         knowledge_base_version
       ) do
    status = if knowledge_base_version.status == :completed, do: :ready, else: :in_progress

    AssistantConfigVersion.changeset(%AssistantConfigVersion{}, %{
      assistant_id: assistant.id,
      prompt: kaapi_config.prompt,
      model: kaapi_config.model,
      provider: "kaapi",
      settings: %{temperature: kaapi_config.temperature},
      status: status,
      organization_id: kaapi_config.organization_id
    })
  end

  @spec update_assistant_with_active_config(map()) :: Ecto.Changeset.t()
  defp update_assistant_with_active_config(%{
         assistant: assistant,
         config_version: config_version
       }) do
    Assistant.set_active_config_version_changeset(assistant, %{
      active_config_version_id: config_version.id
    })
  end

  @spec link_knowledge_base_to_config(
          Ecto.Repo.t(),
          map(),
          KnowledgeBaseVersion.t(),
          non_neg_integer()
        ) :: {:ok, non_neg_integer()}
  defp link_knowledge_base_to_config(
         _repo,
         %{config_version: config_version},
         knowledge_base_version,
         organization_id
       ) do
    {count, _} =
      Repo.insert_all(
        "assistant_config_version_knowledge_base_versions",
        [
          %{
            assistant_config_version_id: config_version.id,
            knowledge_base_version_id: knowledge_base_version.id,
            organization_id: organization_id,
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          }
        ]
      )

    {:ok, count}
  end

  @spec handle_transaction_result({:ok, map()} | {:error, atom(), any(), map()}) ::
          {:ok, map()} | {:error, any()}
  defp handle_transaction_result(result) do
    case result do
      {:ok, %{updated_assistant: assistant, config_version: config_version}} ->
        {:ok, %{assistant: assistant, config_version: config_version}}

      {:error, :assistant, %Ecto.Changeset{} = changeset, _} ->
        {:error, changeset}

      {:error, :config_version, %Ecto.Changeset{} = changeset, _} ->
        {:error, changeset}

      {:error, :updated_assistant, %Ecto.Changeset{} = changeset, _} ->
        {:error, changeset}

      {:error, failed_operation, failed_value, _changes_so_far} ->
        Logger.error("Failed at #{failed_operation}: #{inspect(failed_value)}")

        {:error, "Failed at #{failed_operation}: #{inspect(failed_value)}"}
    end
  end

  @spec generate_temp_name(String.t() | nil, String.t()) :: String.t()
  defp generate_temp_name(name, artifact) when name in [nil, ""] do
    uid = Ecto.UUID.generate() |> String.split("-") |> List.first()
    "#{artifact}-#{uid}"
  end

  defp generate_temp_name(name, _artifact), do: name
end
