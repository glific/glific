defmodule Glific.OpenAI.Filesearch.ApiClient do
  @moduledoc """
  Glific module for API calls to OpenAI related to Filesearch
  """

  use Tesla
  alias Tesla.Multipart

  require Logger
  @endpoint "https://api.openai.com/v1"

  @spec headers() :: list()
  defp headers do
    open_ai_key = Glific.get_open_ai_key()

    [
      {"Authorization", "Bearer #{open_ai_key}"},
      {"Content-Type", "application/json"},
      {"OpenAI-Beta", "assistants=v2"}
    ]
  end

  # using "Content-Type: application/json" in the file upload API caused intermittent errors
  # because OpenAI's handling of this header was inconsistent. Removing the Content-Type header
  # from the upload request resolved the issue.
  @spec remove_content_type(list()) :: list()
  defp remove_content_type(headers) do
    Enum.reject(headers, fn {key, _} -> String.downcase(key) == "content-type" end)
  end

  plug(Tesla.Middleware.JSON, engine_opts: [keys: :atoms])

  @doc """
  Create a VectorStore
  """
  @spec create_vector_store(map()) :: {:ok, map()} | {:error, String.t()}
  def create_vector_store(params) do
    url = @endpoint <> "/vector_stores"

    payload =
      params
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

    tesla_opts = [
      headers: remove_content_type(headers()),
      opts: [adapter: [recv_timeout: 20_000]]
    ]

    url
    |> post(data, tesla_opts)
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
    |> case do
      {:ok, %{deleted: true} = body} ->
        {:ok, body}

      {:ok, _} ->
        {:error, "Not able to delete the file from openAI"}

      err ->
        err
    end
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

  @doc """
  Create an Assistant
  """
  @spec create_assistant(map()) :: {:ok, map()} | {:error, String.t()}
  def create_assistant(params) do
    url = @endpoint <> "/assistants"

    payload =
      %{
        "name" => params.name,
        "model" => params.model,
        "instructions" => params.instructions,
        "temperature" => params.temperature,
        "tools" => [%{"type" => "file_search"}],
        "tool_resources" => %{
          "file_search" => %{
            "vector_store_ids" => params.vector_store_ids
          }
        }
      }
      |> Jason.encode!()

    post(url, payload, headers: headers())
    |> parse_response()
  end

  @doc """
  Delete an Assistant
  """
  @spec delete_assistant(String.t()) :: {:ok, map()} | {:error, String.t()}
  def delete_assistant(assistant_id) do
    url = @endpoint <> "/assistants/#{assistant_id}"

    delete(url, headers: headers())
    |> parse_response()
  end

  @doc """
  Update an Assistant
  """
  @spec modify_assistant(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  def modify_assistant(assistant_id, params) do
    url = @endpoint <> "/assistants/#{assistant_id}"

    payload = %{
      "name" => params.name,
      "model" => params.model,
      "instructions" => params.instructions || "",
      "temperature" => params.temperature
    }

    if Map.has_key?(params, :vector_store_ids) do
      Map.merge(payload, %{
        "tool_resources" => %{
          "file_search" => %{
            "vector_store_ids" => params.vector_store_ids
          }
        }
      })
    else
      payload
    end
    |> Jason.encode!()
    |> then(&post(url, &1, headers: headers()))
    |> parse_response()
  end

  @doc """
  Create vectorStore files in batch.

  We can pass a list of fileIds to be attached to the given VectorStore
  """
  @spec create_vector_store_file_batch(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  def create_vector_store_file_batch(vector_store_id, params) do
    url = @endpoint <> "/vector_stores/#{vector_store_id}/file_batches"

    payload =
      params
      |> Jason.encode!()

    post(url, payload, headers: headers())
    |> parse_response()
  end

  @doc """
  Fetch all available openAI models
  """
  @spec list_models :: {:ok, map()} | {:error, String.t()}
  def list_models do
    url = @endpoint <> "/models"

    get(url, headers: headers())
    |> parse_response()
  end

  @doc """
  Fetch the assistant details
  """
  @spec retrieve_assistant(String.t()) :: {:ok, map()} | {:error, String.t()}
  def retrieve_assistant(assistant_id) do
    url = @endpoint <> "/assistants/#{assistant_id}"

    get(url, headers: headers())
    |> parse_response()
  end

  @doc """
  Fetch the vector store details
  """
  @spec retrieve_vector_store(String.t()) :: {:ok, map()} | {:error, String.t()}
  def retrieve_vector_store(vector_store_id) do
    url = @endpoint <> "/vector_stores/#{vector_store_id}"

    get(url, headers: headers())
    |> parse_response()
  end

  @doc """
  Fetch the vector store file details
  """
  @spec retrieve_vector_store_files(String.t()) :: {:ok, map()} | {:error, String.t()}
  def retrieve_vector_store_files(vector_store_id) do
    url = @endpoint <> "/vector_stores/#{vector_store_id}/files"

    get(url, headers: headers())
    |> parse_response()
  end

  @doc """
  Fetch the openAI file details
  """
  @spec retrieve_file(String.t()) :: {:ok, map()} | {:error, String.t()}
  def retrieve_file(file_id) do
    url = @endpoint <> "/files/#{file_id}"

    get(url, headers: headers())
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
