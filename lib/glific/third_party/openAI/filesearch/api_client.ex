defmodule Glific.OpenAI.Filesearch.ApiClient do
  @moduledoc """
  Glific module for API calls to OpenAI related to Filesearch
  """
  alias Glific.Repo
  alias Glific.Partners
  alias Tesla.Multipart
  require Logger
  @endpoint "https://api.openai.com/v1"
  use Tesla

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

    post(url, data, headers: remove_content_type(headers()))
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
  @spec create_assistant(map()) :: {:ok, map()} | {:error, String.t()}
  def create_assistant(params) do
    url = @endpoint <> "/assistants"

    payload =
      %{
        "name" => params.name,
        "model" => params.model,
        "instructions" => params[:instructions],
        "temperature" => params.temperature,
        "tools" => [%{"type" => "file_search"}],
        "tool_resources" => %{
          "file_search" => %{
            "vector_store_ids" => params.vector_store_ids
          }
        }
      }
      |> Jason.encode!()

    with {:ok, openai_response} <- post(url, payload, headers: headers()) |> parse_response(),
         :ok <- sync_with_kaapi_create(openai_response, params.organization_id) do
      {:ok, openai_response}
    else
      error -> error
    end
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

    base_payload = %{
      "name" => params.name,
      "model" => params.model,
      "instructions" => params.instructions || "",
      "temperature" => params.temperature
    }

    payload =
      if Map.has_key?(params, :vector_store_ids) do
        Map.merge(base_payload, %{
          "tool_resources" => %{
            "file_search" => %{
              "vector_store_ids" => params.vector_store_ids
            }
          }
        })
      else
        base_payload
      end
      |> Jason.encode!()

    with {:ok, updated_data} <-
           post(url, payload, headers: headers()) |> parse_response(),
         :ok <- sync_with_kaapi(assistant_id, updated_data, params.organization_id) do
      {:ok, updated_data}
    else
      error -> error
    end
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

  @spec sync_with_kaapi_create(map(), non_neg_integer()) :: :ok | {:error, String.t()}
  defp sync_with_kaapi_create(openai_data, org_id) do
    kaapi_payload =
      %{
        name: openai_data.name,
        model: openai_data.model,
        instructions: openai_data.instructions || "you are a helpful asssitant",
        temperature: openai_data.temperature,
        vector_store_ids: get_in(openai_data, [:tool_resources, :file_search, :vector_store_ids])
      }
      |> IO.inspect()

    make_kaapi_request("api/v1/assistant", kaapi_payload, org_id, :post)
    |> IO.inspect()
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @spec sync_with_kaapi(String.t(), map(), non_neg_integer()) :: :ok | {:error, String.t()}
  defp sync_with_kaapi(assistant_id, updated_data, org_id) do
    kaapi_payload =
      %{
        name: updated_data.name,
        model: updated_data.model,
        instructions: updated_data.instructions || "",
        temperature: updated_data.temperature,
        vector_store_ids:
          get_in(updated_data, [:tool_resources, :file_search, :vector_store_ids]) || []
      }
      |> IO.inspect()

    case make_kaapi_request("api/v1/assistant/#{assistant_id}", kaapi_payload, org_id, :patch) do
      {:ok, _} -> :ok
      error -> error
    end
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

  @spec make_kaapi_request(String.t(), map(), non_neg_integer(), atom()) ::
          {:ok, map()} | {:error, String.t()}
  defp make_kaapi_request(endpoint, params, organization_id, method) do
    with {:ok, %{"api_key" => key}} <- fetch_kaapi_creds(organization_id) do
      IO.inspect(key)

      header = [
        {"X-API-KEY", key},
        {"Content-Type", "application/json"}
      ]

      kaapi_base_url = Application.fetch_env!(:glific, :kaapi_endpoint) |> IO.inspect()
      url = kaapi_base_url <> endpoint
      request_body = if map_size(params) > 0, do: Jason.encode!(params), else: ""

      case method do
        :delete -> delete(url, headers: header)
        :post -> post(url, request_body, headers: header)
        :patch -> patch(url, request_body, headers: header)
      end
      |> IO.inspect()
      |> parse_kaapi_response()
    end
  end

  @spec org_id() :: non_neg_integer()
  defp org_id do
    Repo.get_organization_id()
  end

  @doc """
  fetch the kaapi credentials
  """
  @spec fetch_kaapi_creds(non_neg_integer) :: nil | {:ok, any} | {:error, any}
  def fetch_kaapi_creds(organization_id) do
    organization = Partners.organization(organization_id)

    organization.services["kaapi"]
    |> case do
      nil ->
        {:error, "Kaapi is not active"}

      credentials ->
        {:ok, credentials.secrets}
    end
  end

  @spec parse_kaapi_response(Tesla.Env.result()) :: {:ok, map()} | {:error, String.t()}
  defp parse_kaapi_response(
         {:ok, %Tesla.Env{status: status, body: %{error: nil, data: data, success: true}}}
       )
       when status in 200..299 do
    data =
      if Map.has_key?(data, :assistant_id) do
        Map.put(data, :id, data.assistant_id)
      else
        data
      end

    {:ok, data}
  end

  defp parse_kaapi_response({:ok, %Tesla.Env{body: %{error: error_msg}}})
       when is_binary(error_msg) do
    Logger.error("kaapi_url api error due to #{inspect(error_msg)}")
    {:error, error_msg}
  end

  defp parse_kaapi_response({:error, message}) do
    Logger.error("Kaapi api error due to #{inspect(message)}")
    {:error, "API request failed"}
  end
end
