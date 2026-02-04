defmodule GlificWeb.Resolvers.Filesearch do
  @moduledoc """
  Filesearch Resolver which sits between the GraphQL schema and Glific Filesearch API.
  """

  alias Glific.{
    Assistants,
    Filesearch,
    Filesearch.VectorStore,
    Repo
  }

  @doc """
  Uploads a file to openAI

  Returns the File details
  """
  @spec upload_file(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def upload_file(_, params, %{context: %{current_user: _user}}) do
    Filesearch.upload_file(params)
  end

  @doc """
  Create an Assistant
  """
  @spec create_assistant(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_assistant(_, %{input: params}, _) do
    Filesearch.create_assistant(params)
  end

  @doc """
  Deletes the Assistant for the given ID
  """
  @spec delete_assistant(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any()} | {:error, any()}
  def delete_assistant(_, params, _) do
    with {:ok, assistant} <- Filesearch.delete_assistant(params.id) do
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
  Removes the given file from the Assistant's VectorStore
  """
  @spec remove_assistant_file(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any()} | {:error, any()}
  def remove_assistant_file(_, params, _) do
    with {:ok, assistant} <- Filesearch.remove_assistant_file(params) do
      {:ok, %{assistant: assistant}}
    end
  end

  @doc """
  Updates an Assistant
  """
  @spec update_assistant(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_assistant(_, %{id: id, input: attrs}, %{context: %{current_user: _user}}) do
    with {:ok, assistant} <- Filesearch.update_assistant(id, attrs) do
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
  Fetch available openai models
  """
  @spec list_models(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any()} | {:error, any()}
  def list_models(_, _params, _) do
    {:ok, Filesearch.list_models()}
  end

  @doc """
  Return the details of the files in a VectorStore
  """
  @spec list_files(VectorStore.t(), map(), map()) :: {:ok, list()}
  def list_files(vector_store, _args, _context) do
    Enum.map(vector_store.files, fn {id, info} ->
      %{id: id, name: info["filename"], uploaded_at: info["uploaded_at"]}
    end)
    |> then(&{:ok, &1})
  end

  @doc """
  Resolves the vector_store field on an assistant.
  Handles both unified API (map with __vector_store_data__) and legacy (Filesearch.Assistant struct) paths.
  """
  @spec resolve_vector_store(map(), map(), map()) :: {:ok, map() | nil}
  def resolve_vector_store(%{__vector_store_data__: vs_data}, _args, _context) do
    {:ok, vs_data}
  end

  def resolve_vector_store(%Glific.Filesearch.Assistant{} = assistant, _args, _context) do
    assistant = Repo.preload(assistant, :vector_store)
    {:ok, assistant.vector_store}
  end

  @doc """
  Calculate the total file size linked to the VectorStore
  """
  @spec calculate_vector_store_size(VectorStore.t(), map(), map()) :: {:ok, String.t()}
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
