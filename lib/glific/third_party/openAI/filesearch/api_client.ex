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
    open_ai_key = Glific.get_open_ai_key()

    [
      {"Authorization", "Bearer #{open_ai_key}"},
      {"Content-Type", "application/json"},
      {"OpenAI-Beta", "assistants=v2"}
    ]
  end

  plug(Tesla.Middleware.JSON, engine_opts: [keys: :atoms])
  plug Tesla.Middleware.FollowRedirects

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
    if FunWithFlags.enabled?(:is_kaapi_enabled, for: %{organization_id: params.organization_id}) do
      kaapi_params = %{
        name: params.name,
        instructions: "String should have at least 10 characters",
        model: params.model,
        vector_store_ids: params.vector_store_ids,
        temperature: params.temperature
      }

      make_kaapi_request("api/v1/assistant", kaapi_params, params.organization_id, :post)
    else
      openai_params = %{
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

      make_openai_request("/assistants", openai_params)
    end
  end

  @doc """
  Delete an Assistant
  """
  @spec delete_assistant(String.t()) :: {:ok, map()} | {:error, String.t()}
  def delete_assistant(assistant_id) do
    if FunWithFlags.enabled?(:is_kaapi_enabled, for: %{organization_id: org_id()}) do
      make_kaapi_request("api/v1/assistant/#{assistant_id}", %{}, org_id(), :delete)
    else
      url = @endpoint <> "/assistants/#{assistant_id}"

      delete(url, headers: headers())
      |> parse_response()
    end
  end

  @doc """
  Update an Assistant
  """
  @spec modify_assistant(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  def modify_assistant(assistant_id, params) do
    if FunWithFlags.enabled?(:is_kaapi_enabled, for: %{organization_id: params.organization_id}) do
      kaapi_params = %{
        name: params.name,
        model: params.model,
        instructions: params.instructions || "",
        temperature: params.temperature,
        vector_store_ids: params[:vector_store_ids]
      }

      make_kaapi_request(
        "api/v1/assistant/#{assistant_id}",
        kaapi_params,
        params.organization_id,
        :patch
      )
    else
      openai_params = %{
        "name" => params.name,
        "model" => params.model,
        "instructions" => params.instructions || "",
        "temperature" => params.temperature
      }

      openai_params =
        if Map.has_key?(params, :vector_store_ids) do
          Map.merge(openai_params, %{
            "tool_resources" => %{
              "file_search" => %{
                "vector_store_ids" => params.vector_store_ids
              }
            }
          })
        else
          openai_params
        end

      make_openai_request("/assistants/#{assistant_id}", openai_params)
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
    if FunWithFlags.enabled?(:is_kaapi_enabled, for: %{organization_id: org_id()}) do
      make_kaapi_request("api/v1/assistant/#{assistant_id}/ingest", %{}, org_id(), :post)
    else
      url = @endpoint <> "/assistants/#{assistant_id}"

      get(url, headers: headers())
      |> parse_response()
    end
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

  @spec make_openai_request(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  defp make_openai_request(endpoint, params) do
    url = @endpoint <> endpoint

    post(url, Jason.encode!(params), headers: headers())
    |> parse_response()
  end

  @spec make_kaapi_request(String.t(), map(), non_neg_integer(), atom()) ::
          {:ok, map()} | {:error, String.t()}
  defp make_kaapi_request(endpoint, params, organization_id, method) do
    with {:ok, %{"api_key" => key}} <- Glific.Flows.Action.fetch_kaapi_creds(organization_id) do
      header = [
        {"X-API-KEY", key},
        {"Content-Type", "application/json"}
      ]

      kaapi_url = Application.fetch_env!(:glific, :kaapi_endpoint)
      url = kaapi_url <> endpoint
      request_body = if map_size(params) > 0, do: Jason.encode!(params), else: ""

      case method do
        :delete -> delete(url, headers: header)
        :post -> post(url, request_body, headers: header)
        :patch -> patch(url, request_body, headers: header)
      end
      |> parse_kaapi_response()
    end
  end

  @spec org_id() :: String.t()
  defp org_id do
    Glific.Partners.Saas.organization_id()
  end
end
