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
  Updates an Assistant by creating a new config version and setting it as active.
  """
  @spec update_assistant(integer(), map()) :: {:ok, map()} | {:error, any()}
  def update_assistant(id, user_params) do
    with {:ok, assistant} <- Repo.fetch_by(Assistant, %{id: id}),
         assistant <- Repo.preload(assistant, :active_config_version),
         merged_params <- merge_with_existing(assistant, user_params),
         :ok <- validate_knowledge_base_presence(merged_params),
         {:ok, knowledge_base_version} <-
           KnowledgeBaseVersion.get_knowledge_base_version(merged_params[:knowledge_base_id]),
         {:ok, kaapi_config} <- build_kaapi_config(merged_params, knowledge_base_version) do
      update_assistant_transaction(assistant, kaapi_config, knowledge_base_version)
    end
  end

  @doc """
  Creates an Assistant with its first config version.
  """
  @spec create_assistant(map()) :: {:ok, map()} | {:error, any()}
  def create_assistant(user_params) do
    with :ok <- validate_knowledge_base_presence(user_params),
         {:ok, knowledge_base_version} <-
           KnowledgeBaseVersion.get_knowledge_base_version(user_params[:knowledge_base_id]),
         {:ok, kaapi_config} <- build_kaapi_config(user_params, knowledge_base_version) do
      create_assistant_transaction(kaapi_config, knowledge_base_version)
    end
  end

  @spec merge_with_existing(Assistant.t(), map()) :: map()
  defp merge_with_existing(assistant, user_params) do
    acv = assistant.active_config_version

    %{
      name: user_params[:name] || assistant.name,
      description: user_params[:description] || acv.description,
      instructions: user_params[:instructions] || acv.prompt,
      temperature: user_params[:temperature] || acv.settings["temperature"],
      model: user_params[:model] || acv.model,
      organization_id: assistant.organization_id,
      knowledge_base_id: user_params[:knowledge_base_id]
    }
  end

  @spec update_assistant_transaction(Assistant.t(), map(), KnowledgeBaseVersion.t()) ::
          {:ok, map()} | {:error, any()}
  defp update_assistant_transaction(assistant, kaapi_config, knowledge_base_version) do
    Multi.new()
    |> Multi.insert(
      :config_version,
      build_config_version_changeset(assistant, kaapi_config, knowledge_base_version)
    )
    |> Multi.update(:updated_assistant, fn %{config_version: config_version} ->
      Assistant.changeset(assistant, %{
        name: kaapi_config.name,
        description: kaapi_config.prompt,
        active_config_version_id: config_version.id
      })
    end)
    |> Multi.insert_all(
      :link_knowledge_base,
      "assistant_config_version_knowledge_base_versions",
      &build_knowledge_base_link(
        &1.config_version,
        knowledge_base_version,
        kaapi_config.organization_id
      )
    )
    |> Multi.run(:kaapi_sync, fn _repo, _changes ->
      create_kaapi_assistant(kaapi_config, kaapi_config.organization_id)
    end)
    |> Repo.transaction()
    |> handle_update_transaction_result()
  end

  @spec handle_update_transaction_result({:ok, map()} | {:error, atom(), any(), map()}) ::
          {:ok, map()} | {:error, any()}
  defp handle_update_transaction_result(result) do
    case result do
      {:ok, %{updated_assistant: assistant, config_version: config_version}} ->
        {:ok, %{assistant: assistant, config_version: config_version}}

      {:error, _failed, %Ecto.Changeset{} = changeset, _} ->
        {:error, changeset}

      {:error, failed_operation, failed_value, _changes_so_far} ->
        Logger.error("Failed at #{failed_operation}: #{inspect(failed_value)}")
        {:error, "Failed at #{failed_operation}: #{inspect(failed_value)}"}
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
    description = user_params[:description] || "Assistant configuration"

    config = %{
      temperature: user_params[:temperature] || 1,
      model: user_params[:model] || @default_model,
      organization_id: user_params[:organization_id],
      name: generate_assistant_name(user_params[:name]),
      description: description,
      vector_store_ids: [knowledge_base_version.llm_service_id],
      prompt: prompt
    }

    {:ok, config}
  end

  @spec create_assistant_transaction(map(), KnowledgeBaseVersion.t()) ::
          {:ok, map()} | {:error, any()}
  defp create_assistant_transaction(kaapi_config, knowledge_base_version) do
    Multi.new()
    |> Multi.insert(:assistant, build_assistant_changeset(kaapi_config))
    |> Multi.insert(
      :config_version,
      &build_config_version_changeset(&1.assistant, kaapi_config, knowledge_base_version)
    )
    |> Multi.update(:assistant_with_active_config, fn %{
                                                        assistant: assistant,
                                                        config_version: config_version
                                                      } ->
      Assistant.set_active_config_version_changeset(assistant, %{
        active_config_version_id: config_version.id
      })
    end)
    |> Multi.insert_all(
      :link_knowledge_base,
      "assistant_config_version_knowledge_base_versions",
      &build_knowledge_base_link(
        &1.config_version,
        knowledge_base_version,
        kaapi_config.organization_id
      )
    )
    |> Multi.run(:kaapi_uuid, fn _repo, _changes ->
      create_kaapi_assistant(kaapi_config, kaapi_config.organization_id)
    end)
    |> Multi.update(:updated_assistant, fn %{
                                             assistant_with_active_config: assistant,
                                             kaapi_uuid: kaapi_uuid
                                           } ->
      Assistant.changeset(assistant, %{kaapi_uuid: kaapi_uuid})
    end)
    |> Repo.transaction()
    |> handle_transaction_result()
  end

  @spec build_knowledge_base_link(
          AssistantConfigVersion.t(),
          KnowledgeBaseVersion.t(),
          non_neg_integer()
        ) :: [map()]
  defp build_knowledge_base_link(config_version, knowledge_base_version, organization_id) do
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

  @spec build_assistant_changeset(map()) :: Ecto.Changeset.t()
  defp build_assistant_changeset(kaapi_config) do
    Assistant.changeset(%Assistant{}, %{
      name: kaapi_config.name,
      description: kaapi_config.prompt,
      organization_id: kaapi_config.organization_id
    })
  end

  @spec build_config_version_changeset(Assistant.t(), map(), KnowledgeBaseVersion.t()) ::
          Ecto.Changeset.t()
  defp build_config_version_changeset(assistant, kaapi_config, knowledge_base_version) do
    status =
      if knowledge_base_version.status == :completed,
        do: :ready,
        else: knowledge_base_version.status

    AssistantConfigVersion.changeset(%AssistantConfigVersion{}, %{
      assistant_id: assistant.id,
      description: kaapi_config.description,
      prompt: kaapi_config.prompt,
      model: kaapi_config.model,
      provider: "kaapi",
      settings: %{temperature: kaapi_config.temperature},
      status: status,
      organization_id: kaapi_config.organization_id
    })
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

  @spec handle_transaction_result({:ok, map()} | {:error, atom(), any(), map()}) ::
          {:ok, map()} | {:error, any()}
  defp handle_transaction_result(result) do
    case result do
      {:ok, %{updated_assistant: assistant, config_version: config_version}} ->
        {:ok, %{assistant: assistant, config_version: config_version}}

      {:error, _failed, %Ecto.Changeset{} = changeset, _} ->
        {:error, changeset}

      {:error, failed_operation, failed_value, _changes_so_far} ->
        Logger.error("Failed at #{failed_operation}: #{inspect(failed_value)}")
        {:error, "Failed at #{failed_operation}: #{inspect(failed_value)}"}
    end
  end

  @spec generate_assistant_name(String.t() | nil) :: String.t()
  defp generate_assistant_name(name) when name in [nil, ""] do
    uid = Ecto.UUID.generate() |> String.split("-") |> List.first()
    "Assistant-#{uid}"
  end

  defp generate_assistant_name(name), do: name
end
