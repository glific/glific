defmodule Glific.Assistants do
  @moduledoc """
  Context module for Assistant and related schemas
  """

  alias Ecto.Multi
  alias Glific.Assistants.Assistant
  alias Glific.Assistants.AssistantConfigVersion
  alias Glific.Assistants.KnowledgeBase
  alias Glific.Assistants.KnowledgeBaseVersion
  alias Glific.Partners
  alias Glific.Repo
  alias Glific.ThirdParty.Kaapi

  require Logger

  defmodule Error do
    @moduledoc """
    Custom error module for Assistant failures.
    Reporting these failures to AppSignal lets us detect and fix problems.
    """
    defexception [:message, :reason, :organization_id]
  end

  @default_model "gpt-4o"
  # https://platform.openai.com/docs/assistants/tools/file-search#supported-files
  @assistant_supported_file_extensions [
    "csv",
    "doc",
    "docx",
    "html",
    "java",
    "md",
    "pdf",
    "pptx",
    "txt"
  ]

  @knowledge_base_version_status_mapping %{
    "SUCCESSFUL" => :completed,
    "FAILED" => :failed,
    "PROCESSING" => :in_progress
  }

  @assistant_config_version_status_mapping %{
    "SUCCESSFUL" => :ready,
    "FAILED" => :failed,
    "PROCESSING" => :in_progress
  }

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
  Updates a Knowledge Base Version.

  ## Examples

  iex> Glific.Assistants.update_knowledge_base_version(%KnowledgeBaseVersion{id: 1}, %{status: :completed})
  {:ok, %KnowledgeBaseVersion{name: "Test KB", organization_id: 1}}

  iex> Glific.Assistants.update_knowledge_base_version(%KnowledgeBaseVersion{id: 1}, %{status: :invalid})
  {:error, %Ecto.Changeset{}}
  """
  @spec update_knowledge_base_version(KnowledgeBaseVersion.t(), map()) ::
          {:ok, KnowledgeBaseVersion.t()} | {:error, Ecto.Changeset.t()}
  def update_knowledge_base_version(knowledge_base_version, params) do
    knowledge_base_version
    |> KnowledgeBaseVersion.changeset(params)
    |> Repo.update()
  end

  @doc """
  Creates an Assistant
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

  @doc """
  Updates an Assistant Version.
  """
  @spec update_assistant_version(AssistantConfigVersion.t(), map()) ::
          {:ok, AssistantConfigVersion.t()} | {:error, Ecto.Changeset.t()}
  def update_assistant_version(assistant_version, params) do
    assistant_version
    |> AssistantConfigVersion.changeset(params)
    |> Repo.update()
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
      {:ok, kaapi_response} ->
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

  @doc """
  Upload file to Kaapi documents API

  ## Parameters
    - params: Map containing:
      - media: Required. Map with:
        - path: Required. File path of the document to upload
        - filename: Required. Name of the file being uploaded
      - target_format: Optional. Desired output format (e.g., pdf, docx, txt) only pdf to markdown is available now
      - callback_url: Optional. URL to call for transformation status updates

  ## Returns
    - {:ok, %{file_id: string, filename: string}}
    - {:error, reason}
  """
  @spec upload_file(map(), non_neg_integer()) ::
          {:ok, map()} | {:error, String.t()}
  def upload_file(params, organization_id) do
    document_params = %{
      path: params.media.path,
      filename: params.media.filename,
      target_format: params[:target_format],
      callback_url: params[:callback_url]
    }

    with {:ok, _} <- validate_file_format(params.media.filename),
         {:ok, %{data: document_data}} <- Kaapi.upload_document(document_params, organization_id) do
      {:ok,
       %{
         file_id: document_data[:id],
         filename: document_data[:fname],
         uploaded_at: document_data[:inserted_at]
       }}
    else
      {:error, %{status: status, body: body}} ->
        error_message = body[:error]
        {:error, "File upload failed (status #{status}): #{error_message}"}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "File upload failed: #{inspect(reason)}"}
    end
  end

  @spec validate_file_format(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp validate_file_format(filename) do
    extension = String.split(filename, ".") |> List.last()

    if extension in @assistant_supported_file_extensions do
      {:ok, filename}
    else
      {:error, "Files with extension '.#{extension}' not supported in Assistants"}
    end
  end

  @doc """
    Create a new knowledge base, knowledge_base_version in Glific and creates a corresponding Collection in Kaapi.
  """
  @spec create_knowledge_base_with_version(params :: map()) ::
          {:ok, map()} | {:error, Ecto.Changeset.t() | String.t()}
  def create_knowledge_base_with_version(params) do
    with {:ok, knowledge_base} <- maybe_create_knowledge_base(params),
         {:ok, knowledge_base_version} <-
           build_and_create_knowledge_base_version(knowledge_base, params),
         api_params <- prepare_kaapi_collections_api_params(knowledge_base_version, params),
         {:ok, %{data: %{job_id: job_id}}} <-
           Kaapi.create_collection(api_params, params[:organization_id]),
         {:ok, knowledge_base_version} <-
           update_knowledge_base_version(knowledge_base_version, %{kaapi_job_id: job_id}) do
      {:ok, %{knowledge_base_version: knowledge_base_version, knowledge_base: knowledge_base}}
    else
      {:error, %Ecto.Changeset{} = error} ->
        {:error, error}

      {:error, error} ->
        Glific.log_exception(%Error{
          message: "Create knowledge base failed. Reason: #{inspect(error)}",
          reason: inspect(error)
        })

        {:error, "Failed to create knowledge base"}
    end
  end

  @doc """
  Handles the callback from Kaapi for knowledge base creation.
  """
  @spec handle_kaapi_knowledge_base_callback(map) ::
          KnowledgeBaseVersion.t() | {:error, String.t()}
  def handle_kaapi_knowledge_base_callback(%{"data" => %{"job_id" => job_id} = data}) do
    knowledge_base_version_params =
      case get_in(data, ["collection", "llm_service_id"]) do
        nil -> %{status: data["status"]}
        llm_service_id -> %{status: data["status"], llm_service_id: llm_service_id}
      end

    assistant_version_params = %{status: data["status"], failure_reason: data["error_message"]}

    with {:ok, knowledge_base_version} <-
           Repo.fetch_by(KnowledgeBaseVersion, %{kaapi_job_id: job_id}),
         {:ok, knowledge_base_version} <-
           update_knowledge_base_version_status_and_llm_service_id(
             knowledge_base_version,
             knowledge_base_version_params
           ),
         :ok <-
           update_linked_assistant_versions(knowledge_base_version, assistant_version_params) do
      knowledge_base_version
    else
      {:error, [_, "Resource not found"]} ->
        Logger.error(
          "Failed to update knowledge base version status, Knowledge Base Version not found. Job ID: #{job_id}"
        )

        {:error, "Failed to update knowledge base version status"}

      {:error, :failed} ->
        Logger.error("Knowledge Base Version already failed, Job ID: #{job_id}")

        {:error, "Failed to update knowledge base version status"}
    end
  end

  # Private
  @spec maybe_create_knowledge_base(map()) ::
          {:ok, KnowledgeBase.t()} | {:error, Ecto.Changeset.t()}
  defp maybe_create_knowledge_base(%{id: id}), do: Repo.fetch(KnowledgeBase, id)

  defp maybe_create_knowledge_base(params) do
    params = %{name: generate_knowledge_base_name(), organization_id: params[:organization_id]}
    create_knowledge_base(params)
  end

  @spec build_and_create_knowledge_base_version(KnowledgeBase.t(), map()) ::
          {:ok, KnowledgeBaseVersion.t()} | {:error, Ecto.Changeset.t()}
  defp build_and_create_knowledge_base_version(knowledge_base, params) do
    files_details =
      Enum.reduce(params.media_info, %{}, fn info, files ->
        Map.put(files, info.file_id, info)
      end)

    params = %{
      knowledge_base_id: knowledge_base.id,
      organization_id: params[:organization_id],
      files: files_details,
      status: :in_progress,
      llm_service_id: generate_temporary_llm_service_id()
    }

    create_knowledge_base_version(params)
  end

  @spec generate_knowledge_base_name() :: String.t()
  defp generate_knowledge_base_name do
    uid = Ecto.UUID.generate() |> String.split("-") |> List.first()
    "Vector-Store-#{uid}"
  end

  # Temporary LLM Service ID that looks like what is
  # generated by Kaapi or other providers.
  @spec generate_temporary_llm_service_id() :: String.t()
  defp generate_temporary_llm_service_id do
    random_string =
      24
      |> :crypto.strong_rand_bytes()
      |> Base.encode32(case: :lower, padding: false)
      |> binary_part(0, 24)

    "temporary-vs-#{random_string}"
  end

  @spec prepare_kaapi_collections_api_params(KnowledgeBaseVersion.t(), map()) :: map()
  defp prepare_kaapi_collections_api_params(%KnowledgeBaseVersion{files: files}, params) do
    organization = Partners.organization(params[:organization_id])

    callback_url =
      "https://api.#{organization.shortcode}.glific.com" <>
        "/kaapi/knowledge_base_version"

    %{
      documents: Map.keys(files),
      callback_url: callback_url
    }
  end

  @spec update_knowledge_base_version_status_and_llm_service_id(KnowledgeBaseVersion.t(), map()) ::
          {:ok, KnowledgeBaseVersion.t()} | {:error, Ecto.Changeset.t()}
  defp update_knowledge_base_version_status_and_llm_service_id(%{status: :failed}, _),
    do: {:error, :failed}

  defp update_knowledge_base_version_status_and_llm_service_id(
         knowledge_base_version,
         %{status: status} = params
       ) do
    params = Map.put(params, :status, @knowledge_base_version_status_mapping[status])
    update_knowledge_base_version(knowledge_base_version, params)
  end

  @spec update_linked_assistant_versions(KnowledgeBaseVersion.t(), map()) :: :ok
  defp update_linked_assistant_versions(knowledge_base_version, %{status: status} = params) do
    knowledge_base_version = Repo.preload(knowledge_base_version, :assistant_config_versions)
    params = Map.put(params, :status, @assistant_config_version_status_mapping[status])

    Enum.each(knowledge_base_version.assistant_config_versions, fn assistant_version ->
      update_assistant_version(assistant_version, params)
    end)
  end
end
