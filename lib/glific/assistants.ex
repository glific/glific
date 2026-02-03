defmodule Glific.Assistants do
  @moduledoc """
  Context module for the Unified API assistants.
  """

  import Ecto.Query

  alias Glific.{
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Repo
  }

  @doc """
  Lists assistants from the unified API tables, transformed to legacy shape.
  """
  @spec list_assistants(map()) :: list(map())
  def list_assistants(args) do
    assistants =
      args
      |> Repo.list_filter_query(Assistant, &Repo.opts_with_inserted_at/2, &Repo.filter_with/2)
      |> Repo.all()

    assistants =
      Repo.preload(assistants, [
        {:active_config_version, [knowledge_base_versions: :knowledge_base]},
        config_versions:
          from(cv in AssistantConfigVersion,
            where: cv.status == :in_progress
          )
      ])

    Enum.map(assistants, &transform_to_legacy_shape/1)
  end

  @doc """
  Gets a single assistant from the unified API tables, transformed to legacy shape.
  """
  @spec get_assistant(integer()) :: {:ok, map()} | {:error, any()}
  def get_assistant(id) do
    with {:ok, assistant} <- Repo.fetch_by(Assistant, %{id: id}) do
      assistant =
        Repo.preload(assistant, [
          {:active_config_version, [knowledge_base_versions: :knowledge_base]},
          config_versions:
            from(cv in AssistantConfigVersion,
              where: cv.status == :in_progress
            )
        ])

      {:ok, transform_to_legacy_shape(assistant)}
    end
  end

  @doc """
  Transforms a unified API Assistant struct into a map matching the legacy
  GraphQL assistant response shape.
  """
  @spec transform_to_legacy_shape(Assistant.t()) :: map()
  def transform_to_legacy_shape(%Assistant{} = assistant) do
    acv = assistant.active_config_version

    new_version_in_progress =
      case assistant.config_versions do
        versions when is_list(versions) ->
          Enum.any?(versions, fn cv ->
            cv.id != assistant.active_config_version_id and cv.status == :in_progress
          end)

        _ ->
          false
      end

    %{
      id: assistant.id,
      name: assistant.name,
      assistant_id: acv.kaapi_uuid,
      temperature: get_in(acv.settings || %{}, ["temperature"]),
      model: acv.model,
      instructions: acv.prompt,
      status: to_string(acv.status),
      new_version_in_progress: new_version_in_progress,
      __vector_store_data__: build_vector_store_data(acv),
      inserted_at: assistant.inserted_at,
      updated_at: assistant.updated_at
    }
  end

  defp build_vector_store_data(acv) do
    case acv.knowledge_base_versions do
      [kbv | _] ->
        kb = kbv.knowledge_base

        %{
          id: kb.id,
          vector_store_id: kbv.llm_service_id,
          name: kb.name,
          files: kbv.files || %{},
          size: kbv.size || 0,
          status: to_string(kbv.status),
          legacy: is_nil(kbv.kaapi_job_id),
          inserted_at: kbv.inserted_at,
          updated_at: kbv.updated_at
        }

      _ ->
        nil
    end
  end
end
