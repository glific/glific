defmodule GlificWeb.Resolvers.Filesearch do
  @moduledoc """
  Filesearch Resolver which sits between the GraphQL schema and Glific Filesearch API.
  """

  alias Glific.{
    Assistants,
    Filesearch,
    Filesearch.VectorStore
  }

  @doc """
  Uploads a file to Kaapi

  Returns the File details
  """
  @spec upload_file(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def upload_file(_, params, %{context: %{current_user: user}}) do
    Assistants.upload_file(params, user.organization_id)
  end

  @doc """
  Create an Assistant
  """
  @spec create_assistant(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_assistant(_, %{input: params}, _) do
    Assistants.create_assistant(params)
  end

  @doc """
  Deletes the Assistant for the given ID
  """
  @spec delete_assistant(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any()} | {:error, any()}
  def delete_assistant(_, params, _) do
    with {:ok, assistant} <- Assistants.delete_assistant(params.id) do
      {:ok, %{assistant: assistant}}
    end
  end

  @doc """
  Upload and add the files to the VectorStore
  """
  @spec add_assistant_files(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def add_assistant_files(_, params, _) do
    with {:ok, assistant} <- Filesearch.add_assistant_files(params) do
      {:ok, %{assistant: assistant}}
    end
  end

  @doc """
  Updates an Assistant
  """
  @spec update_assistant(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_assistant(_, %{id: id, input: attrs}, _) do
    with {:ok, assistant} <- Assistants.update_assistant(id, attrs) do
      {:ok, %{assistant: assistant}}
    end
  end

  @doc """
  Fetch the details for the given Assistant
  """
  @spec get_assistant(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any()} | {:error, any()}
  def get_assistant(_, params, _) do
    with {:ok, assistant} <- Assistants.get_assistant(params.id) do
      {:ok, %{assistant: assistant}}
    end
  end

  @doc """
  Fetch Assistants with given filters and options
  """
  @spec list_assistants(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any()} | {:error, any()}
  def list_assistants(_, params, _) do
    {:ok, Assistants.list_assistants(params)}
  end

  @doc """
  Get count of assistants filtered by various criteria
  """
  @spec count_assistants(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer()}
  def count_assistants(_, params, _) do
    {:ok, Assistants.count_assistants(params)}
  end

  @doc """
  Fetch available openai models
  """
  @spec list_models(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any()} | {:error, any()}
  def list_models(_, _params, _) do
    {:ok, Filesearch.list_models()}
  end

  @doc """
  List all config versions for a given assistant.
  """
  @spec list_assistant_versions(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, list(map())} | {:error, any()}
  def list_assistant_versions(_, %{assistant_id: assistant_id}, _) do
    case Assistants.list_assistant_config_versions(assistant_id) do
      {:error, reason} -> {:error, reason}
      versions -> {:ok, versions}
    end
  end

  @doc """
  Set a specific config version as the live (active) version for an assistant.
  """
  @spec set_live_version(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def set_live_version(_, %{assistant_id: assistant_id, version_id: version_id}, _) do
    with {:ok, result} <- Assistants.set_live_version(assistant_id, version_id) do
      {:ok, %{assistant: result}}
    end
  end

  @doc """
  Return the details of the files in a VectorStore.
  Handles both unified API (map) and legacy (VectorStore struct) data.
  """
  @spec list_files(VectorStore.t(), map(), map()) :: {:ok, list()}
  def list_files(vector_store, _args, _context) do
    Enum.map(vector_store.files, fn {id, info} ->
      %{
        id: id,
        name: info["filename"],
        uploaded_at: info["uploaded_at"],
        file_size: info["file_size"]
      }
    end)
    |> then(&{:ok, &1})
  end

  @doc """
  Resolves the vector_store field on an assistant.
  """
  @spec resolve_vector_store(map(), map(), map()) :: {:ok, map() | nil}
  def resolve_vector_store(%{vector_store_data: vs_data}, _args, _context) do
    {:ok, vs_data}
  end

  @doc """
  Calculate the total file size linked to the VectorStore.
  """
  @spec calculate_vector_store_size(map(), map(), map()) :: {:ok, String.t()}
  def calculate_vector_store_size(vector_store, _args, _context) do
    total_size = vector_store.size
    kb = 1_024
    mb = 1_048_576
    gb = 1_073_741_824

    cond do
      total_size >= gb ->
        size = (total_size / gb) |> Float.round(2)
        to_string(size) <> " GB"

      total_size >= mb ->
        size = (total_size / mb) |> Float.round(2)
        to_string(size) <> " MB"

      total_size >= kb ->
        size = (total_size / kb) |> Float.round(2)
        to_string(size) <> " KB"

      true ->
        to_string(total_size) <> " B"
    end
    |> then(&{:ok, &1})
  end
end
