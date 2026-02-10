defmodule Glific.Assistants do
  @moduledoc """
  Context module for Assistant and related schemas
  """
  alias Glific.Assistants.Assistant
  alias Glific.Assistants.AssistantConfigVersion
  alias Glific.Assistants.KnowledgeBase
  alias Glific.Assistants.KnowledgeBaseVersion
  alias Glific.Repo
  alias Glific.ThirdParty.Kaapi

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
  Creates an Assistant with its first config version.
  This is the main public API for creating assistants.
  """
  @spec create_assistant(map()) :: {:ok, map()} | {:error, any()}
  def create_assistant(params) do
    if is_nil(params[:knowledge_base_id]) do
      {:error, "Knowledge base is required for assistant creation"}
    else
      do_create_assistant_with_kb(params)
    end
  end

  @spec do_create_assistant_with_kb(map()) :: {:ok, map()} | {:error, any()}
  defp do_create_assistant_with_kb(params) do
    org_id = params[:organization_id]
    prompt = params[:instructions] || "You are a helpful assistant"

    kb_details = get_knowledge_base_detail(params[:knowledge_base_id])

    # Additional validation: ensure vector_store_id exists (can be the case for older assistatns)
    if is_nil(kb_details.vector_store_id) do
      {:error, "Knowledge base must have a valid vector store"}
    else
      attrs = %{
        temperature: params[:temperature] || 1,
        model: params[:model] || @default_model,
        organization_id: org_id,
        instructions: prompt,
        name: generate_temp_name(params[:name], "Assistant"),
        vector_store_ids: [kb_details.vector_store_id]
      }

      with {:ok, kaapi_response} <- Kaapi.create_assistant_config(attrs, org_id),
           kaapi_uuid when is_binary(kaapi_uuid) <- kaapi_response.data.id do
        multi_result =
          Ecto.Multi.new()
          |> Ecto.Multi.insert(
            :assistant,
            Assistant.changeset(%Assistant{}, %{
              name: attrs.name,
              description: params[:description],
              kaapi_uuid: kaapi_uuid,
              organization_id: org_id
            })
          )
          |> Ecto.Multi.insert(:config_version, fn %{assistant: assistant} ->
            AssistantConfigVersion.changeset(%AssistantConfigVersion{}, %{
              assistant_id: assistant.id,
              prompt: prompt,
              model: attrs.model,
              provider: "kaapi",
              settings: %{temperature: attrs.temperature},
              status: kb_details.status,
              organization_id: org_id
            })
          end)
          |> Ecto.Multi.update(:updated_assistant, fn %{
                                                        assistant: assistant,
                                                        config_version: config_version
                                                      } ->
            Assistant.set_active_config_version_changeset(assistant, %{
              active_config_version_id: config_version.id
            })
          end)
          |> Ecto.Multi.run(:link_kb, fn _repo, %{config_version: config_version} ->
            if kb_details.kb_version_id do
              {count, _} =
                link_config_to_knowledge_base(
                  config_version.id,
                  kb_details.kb_version_id,
                  org_id
                )

              {:ok, count}
            else
              {:ok, 0}
            end
          end)
          |> Repo.transaction()

        case multi_result do
          {:ok, %{updated_assistant: assistant, config_version: config_version}} ->
            {:ok, %{assistant: assistant, config_version: config_version}}

          {:error, failed_operation, failed_value, _changes_so_far} ->
            {:error, "Failed at #{failed_operation}: #{inspect(failed_value)}"}
        end
      else
        {:error, %{status: _status, body: body}} when is_map(body) ->
          {:error, "Failed to create assistant config in Kaapi: #{body[:error]}"}

        {:error, reason} when is_binary(reason) ->
          {:error, reason}

        {:error, reason} ->
          {:error, "Failed to create assistant: #{inspect(reason)}"}

        _ ->
          {:error, "Failed to create assistant: Something went wrong"}
      end
    end
  end

  @spec generate_temp_name(String.t() | nil, String.t()) :: String.t()
  defp generate_temp_name(name, artifact) when name in [nil, ""] do
    uid = Ecto.UUID.generate() |> String.split("-") |> List.first()
    "#{artifact}-#{uid}"
  end

  defp generate_temp_name(name, _artifact), do: name

  @spec link_config_to_knowledge_base(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), nil | [term()]}
  defp link_config_to_knowledge_base(config_version_id, kb_version_id, org_id) do
    Repo.insert_all(
      "assistant_config_version_knowledge_base_versions",
      [
        %{
          assistant_config_version_id: config_version_id,
          knowledge_base_version_id: kb_version_id,
          organization_id: org_id,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      ]
    )
  end

  @spec get_knowledge_base_detail(nil | integer()) :: map()
  defp get_knowledge_base_detail(nil) do
    %{kb_version_id: nil, status: :ready, vector_store_id: nil}
  end

  defp get_knowledge_base_detail(kb_id) do
    with {:ok, kb_version} <- KnowledgeBaseVersion.get_knowledge_base_version(kb_id) do
      status = if kb_version.status == :completed, do: :ready, else: :in_progress

      %{
        kb_version_id: kb_version.id,
        status: status,
        vector_store_id: kb_version.llm_service_id
      }
    end
  end
end
