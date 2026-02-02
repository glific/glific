defmodule Glific.ThirdParty.Kaapi.ApiClient do
  @moduledoc """
  API Client for Kaapi Integration.
  """

  require Logger

  # client with runtime config (API key / base URL).
  # Set skip_content_type: true for multipart uploads
  defp client(api_key, opts \\ []) do
    Glific.Metrics.increment("Kaapi Requests")
    base_url = kaapi_config(:kaapi_endpoint)

    headers =
      if Keyword.get(opts, :skip_content_type, false) do
        [{"X-API-KEY", api_key}]
      else
        [{"X-API-KEY", api_key}, {"content-type", "application/json"}]
      end

    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, base_url},
        {Tesla.Middleware.Headers, headers},
        {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]},
        {Tesla.Middleware.Telemetry, metadata: %{provider: "Kaapi", sampling_scale: 10}}
      ] ++ Glific.get_tesla_retry_middleware()
    )
  end


  @doc """
  Onboard NGOs to Kaapi
  """
  @spec onboard_to_kaapi(map()) ::
          {:ok, %{data: %{api_key: String.t()}}} | {:error, map() | String.t()}
  def onboard_to_kaapi(params) do
    api_key = kaapi_config(:kaapi_api_key)

    body = %{
      organization_name: params.organization_name,
      project_name: params.project_name
    }

    body =
      if params[:openai_api_key] do
        Map.put(body, :openai_api_key, params[:openai_api_key])
      else
        body
      end

    opts = [adapter: [recv_timeout: 30_000]]

    api_key
    |> client()
    |> Tesla.post("/api/v1/onboard", body, opts: opts)
    |> parse_kaapi_response()
  end

  @doc """
  Calls Kaapi Responses API with the given payload.
  """
  @spec call_responses_api(String.t(), binary()) :: {:ok, any()} | {:error, any()}
  def call_responses_api(payload, org_api_key) do
    opts = [adapter: [recv_timeout: 300_000]]

    org_api_key
    |> client()
    |> Tesla.post("/api/v1/responses", payload, opts: opts)
    |> parse_kaapi_response()
  end

  @doc """
  Create an assistant in Kaapi
  """
  @spec create_assistant(map(), binary()) :: {:ok, map()} | {:error, String.t()}
  def create_assistant(body, org_api_key) do
    org_api_key
    |> client()
    |> Tesla.post("/api/v1/assistant/", body)
    |> parse_kaapi_response()
  end

  @doc """
  Update an assistant in Kaapi
  """
  @spec update_assistant(binary(), map(), binary()) :: {:ok, map()} | {:error, String.t()}
  def update_assistant(assistant_id, body, org_api_key) do
    org_api_key
    |> client()
    |> Tesla.patch("/api/v1/assistant/#{assistant_id}", body)
    |> parse_kaapi_response()
  end

  @doc """
  Delete an assistant in Kaapi
  """
  @spec delete_assistant(binary(), binary()) :: {:ok, map()} | {:error, map() | String.t()}
  def delete_assistant(assistant_id, org_api_key) do
    org_api_key
    |> client()
    |> Tesla.delete("/api/v1/assistant/#{assistant_id}")
    |> parse_kaapi_response()
  end

  @doc """
  Ingests an assistant into the Kaapi platform.
  """
  @spec ingest_ai_assistants(non_neg_integer, String.t()) :: {:ok, any()} | {:error, String.t()}
  def ingest_ai_assistants(org_api_key, assistant_id) do
    opts = [adapter: [recv_timeout: 30_000]]

    org_api_key
    |> client()
    |> Tesla.post("/api/v1/assistant/#{assistant_id}/ingest", %{}, opts: opts)
    |> case do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        {:ok, %{message: "Assistant synced successfully"}}

      {:ok, %Tesla.Env{status: 409}} ->
        # In this API, 409 cannot be considered as a failure so treating it as a special case
        {:ok, %{message: "Assistant already exists in kaapi"}}

      result ->
        parse_kaapi_response(result)
    end
  end

  @doc """
  Upload a document to Kaapi documents API with transformation options.
  """
  @spec upload_document(map(), binary()) :: {:ok, map()} | {:error, String.t()}
  def upload_document(params, org_api_key) do
    content_type = MIME.from_path(params.filename)

    multipart =
      Tesla.Multipart.new()
      |> Tesla.Multipart.add_file(params.path,
        name: "src",
        filename: params.filename,
        headers: [{"content-type", content_type}]
      )

    multipart =
      if params[:target_format] do
        Tesla.Multipart.add_field(multipart, "target_format", params.target_format)
      else
        multipart
      end

    multipart =
      if params[:transformer] do
        Tesla.Multipart.add_field(multipart, "transformer", params.transformer)
      else
        multipart
      end

    multipart =
      if params[:callback_url] do
        Tesla.Multipart.add_field(multipart, "callback_url", params.callback_url)
      else
        multipart
      end

    opts = [adapter: [recv_timeout: 60_000]]

    org_api_key
    |> client(skip_content_type: true)
    |> Tesla.post("/api/v1/documents/", multipart, opts: opts)
    |> parse_kaapi_response()
  end

  # Private
  @spec parse_kaapi_response(Tesla.Env.result()) :: {:ok, map()} | {:error, any()}
  defp parse_kaapi_response({:ok, %Tesla.Env{status: status, body: body}})
       when status in 200..299 do
    {:ok, body}
  end

  defp parse_kaapi_response({:ok, %Tesla.Env{status: status, body: body}}) do
    Glific.Metrics.increment("Kaapi Failed")
    {:error, %{status: status, body: body}}
  end

  defp parse_kaapi_response(error) do
    if {:error, :timeout} == error, do: Glific.Metrics.increment("Kaapi Timedout")
    error
  end

  defp kaapi_config, do: Application.fetch_env!(:glific, __MODULE__)
  defp kaapi_config(key), do: kaapi_config()[key]

end
