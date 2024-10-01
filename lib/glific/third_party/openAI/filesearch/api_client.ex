defmodule Glific.OpenAI.Filesearch.ApiClient do
  @moduledoc """
  Glific module for API calls to OpenAI related to Filesearch
  """
  alias Tesla.Multipart
  require Logger
  @endpoint "https://api.openai.com/v1"
  use Tesla

  @spec headers() :: list()
  defp headers do
    open_ai_key = Glific.get_open_ai_filesearch_key()
    open_ai_project = Glific.get_open_ai_filesearch_project()

    [
      {"Authorization", "Bearer #{open_ai_key}"},
      {"Content-Type", "application/json"},
      {"OpenAI-Beta", "assistants=v2"},
      {"OpenAI-Project", open_ai_project}
    ]
  end

  plug(Tesla.Middleware.JSON, engine_opts: [keys: :atoms])

  @doc """
  Create a VectorStore
  """
  @spec create_vector_store(String.t()) :: {:ok, map()} | {:error, String.t()}
  def create_vector_store(name) do
    url = @endpoint <> "/vector_stores"

    payload =
      %{"name" => name}
      |> Jason.encode!()

    post(url, payload, headers: headers())
    |> parse_response()
  end

  @doc """
  Delete a VectorStore
  """
  @spec delete_vector_store(String.t()) :: {:ok, map()} | {:error, String.t()}
  def delete_vector_store(vector_store_id) do
    url = @endpoint <> "/vector_stores/#{vector_store_id}"

    delete(url, headers: headers())
    |> parse_response()
  end

  @doc """
  Upload file to openAI
  """
  @spec upload_file(map()) :: {:ok, map()} | {:error, String.t()}
  def upload_file(media_info) do
    url = @endpoint <> "/files"

    data =
      Multipart.new()
      |> Multipart.add_file(media_info.path, name: "file", filename: media_info.filename)
      |> Multipart.add_field("purpose", "assistants")

    post(url, data, headers: headers())
    |> parse_response()
  end

  @doc """
  Add an openAI file to VectorStore
  """
  @spec create_vector_store_file(map()) :: {:ok, map()} | {:error, String.t()}
  def create_vector_store_file(params) do
    url = @endpoint <> "/vector_stores/#{params.vector_store_id}/files"

    payload =
      %{"file_id" => params.file_id}
      |> Jason.encode!()

    post(url, payload, headers: headers())
    |> parse_response()
  end

  @doc """
  Remove an openAI file from VectorStore
  """
  @spec delete_vector_store_file(map()) :: {:ok, map()} | {:error, String.t()}
  def delete_vector_store_file(params) do
    url = @endpoint <> "/vector_stores/#{params.vector_store_id}/files/#{params.file_id}"

    delete(url, headers: headers())
    |> parse_response()
  end

  @doc """
  Delete an openAI file
  """
  @spec delete_file(String.t()) :: {:ok, map()} | {:error, String.t()}
  def delete_file(file_id) do
    url = @endpoint <> "/files/#{file_id}"

    delete(url, headers: headers())
    |> parse_response()
  end

  @doc """
  Modify a VectorStore
  """
  @spec modify_vector_store(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  def modify_vector_store(vector_store_id, params) do
    url = @endpoint <> "/vector_stores/#{vector_store_id}"

    payload =
      params
      |> Jason.encode!()

    post(url, payload, headers: headers())
    |> parse_response()
  end

  @spec parse_response(Tesla.Env.result()) :: {:ok, map()} | {:error, String.t()}
  defp parse_response({:ok, %{body: resp_body, status: status}})
       when status >= 200 and status < 300 do
    {:ok, resp_body}
  end

  defp parse_response({:ok, %{body: resp_body, status: status}}) do
    Logger.error("Filesearch api error due to #{inspect(resp_body)} with status #{status}")
    {:error, "#{resp_body.error.message}"}
  end

  defp parse_response({:error, message}) do
    Logger.error("Filesearch api error due to #{inspect(message)}")
    {:error, "OpenAI api failed"}
  end
end
