defmodule Glific.OpenAI.Filesearch do
  @moduledoc """
  Glific module for API calls to OpenAI related to Filesearch
  """
  @endpoint "https://api.openai.com/v1"

  @spec middleware() :: list()
  defp middleware do
    open_ai_key = Glific.get_open_ai_key()

    authorization_variables = [
      {"Authorization", "Bearer #{open_ai_key}"},
      {"Content-Type", "application/json"},
      {"OpenAI-Beta", "assistants=v2"}
    ]

    [{Tesla.Middleware.Headers, authorization_variables}]
  end

  @doc """
  Creates vector store with given name to enable file search
  """
  @spec create_vector_store(String.t()) :: {:ok, map()} | {:error, String.t()}
  def create_vector_store(name) do
    url = @endpoint <> "/vector_stores"

    payload =
      %{"name" => name}
      |> Jason.encode!()

    middleware()
    |> Tesla.client()
    |> Tesla.post(url, payload)
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, %{vector_store_id: Jason.decode!(body)["id"]}}

      {_status, response} ->
        {:error, "Failed to create vector store: #{inspect(response)}"}
    end
  end

  @doc """
    Modifies vector store identified with passed vector_store_id paramater
  """
  @spec modify_vector_store(map()) :: {:ok, map()} | {:error, String.t()}
  def modify_vector_store(params) do
    url = @endpoint <> "/vector_stores/#{params.vector_store_id}"

    payload =
      %{"name" => params.name}
      |> Jason.encode!()

    middleware()
    |> Tesla.client()
    |> Tesla.post(url, payload)
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, %{vector_store_id: Jason.decode!(body)["id"]}}

      {_status, response} ->
        {:error, "Failed to modify vector store: #{inspect(response)}"}
    end
  end

  @doc """
    Deletes vector store identified with passed vector_store_id paramater
  """
  @spec delete_vector_store(String.t()) :: {:ok, map()} | {:error, String.t()}
  def delete_vector_store(vector_store_id) do
    url = @endpoint <> "/vector_stores/#{vector_store_id}"

    middleware()
    |> Tesla.client()
    |> Tesla.delete(url)
    |> case do
      {:ok, %Tesla.Env{status: 200}} ->
        {:ok, %{vector_store_id: vector_store_id}}

      {_status, response} ->
        {:error, "Failed to delete vector store: #{inspect(response)}"}
    end
  end

  @doc """
    Creates assistant with specified instructions for vector store identified with passed vector_store_id paramater
  """
  @spec create_assistant(map()) :: {:ok, map()} | {:error, String.t()}
  def create_assistant(params) do
    url = @endpoint <> "/assistants"

    payload =
      %{
        instructions: params.instructions,
        name: params.name,
        description: params.description,
        tool_resources: %{
          file_search: %{
            vector_store_ids: [params.vector_store_id]
          }
        },
        model: params.model
      }
      |> Jason.encode!()

    middleware()
    |> Tesla.client()
    |> Tesla.post(url, payload)
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, %{assistant_id: Jason.decode!(body)["id"]}}

      {_status, response} ->
        {:error, "Failed to create assistant: #{inspect(response)}"}
    end
  end

  @doc """
    Updates assistant identified with passed assistant_id paramater
  """
  @spec modify_assistant(map()) :: {:ok, map()} | {:error, String.t()}
  def modify_assistant(params) do
    # change may be needed to originally require assistanta_id parameter
    url = @endpoint <> "/assistants/#{params.assistant_id}"

    payload =
      %{
        instructions: params.instructions,
        name: params.name,
        description: params.description,
        tool_resources: %{
          file_search: %{
            vector_store_ids: [params.vector_store_id]
          }
        },
        model: params.model
      }
      |> Jason.encode!()

    middleware()
    |> Tesla.client()
    |> Tesla.post(url, payload)
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, %{assistant_id: Jason.decode!(body)["id"]}}

      {_status, response} ->
        {:error, "Failed to modify assistant: #{inspect(response)}"}
    end
  end

  @doc """
    Deletes assistant identified with passed assistant_id paramater
  """
  @spec delete_assistant(String.t()) :: {:ok, map()} | {:error, String.t()}
  def delete_assistant(assistant_id) do
    url = @endpoint <> "/assistants/#{assistant_id}"

    middleware()
    |> Tesla.client()
    |> Tesla.delete(url)
    |> case do
      {:ok, %Tesla.Env{status: 200}} ->
        {:ok, %{assistant_id: assistant_id}}

      {_status, response} ->
        {:error, "Failed to delete assistant: #{inspect(response)}"}
    end
  end
end
