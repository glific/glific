defmodule Glific.ThirdParty.Kaapi.ApiClient do
  @moduledoc """
  API Client for Kaapi Integration.
  """

  # client with runtime config (API key / base URL).
  defp client(api_key) do
    Tesla.client(middlewares(api_key) ++ Glific.get_tesla_retry_middleware())
  end

  defp client(api_key, adapter) do
    Tesla.client(middlewares(api_key) ++ Glific.get_tesla_retry_middleware(), adapter)
  end

  defp middlewares(api_key) do
    Glific.Metrics.increment("Kaapi Requests")
    base_url = kaapi_config(:kaapi_endpoint)

    [
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.Headers, [{"X-API-KEY", api_key}]},
      {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]},
      Tesla.Middleware.KeepRequest,
      Tesla.Middleware.PathParams,
      {Tesla.Middleware.Logger, filter_headers: ["X-API-KEY"]},
      {Tesla.Middleware.Telemetry, metadata: %{provider: "Kaapi", sampling_scale: 10}}
    ]
  end

  @doc """
  Onboard NGOs to Kaapi
  """
  @spec onboard_to_kaapi(map()) ::
          {:ok, %{data: %{api_key: String.t()}}} | {:error, map() | String.t()}
  def onboard_to_kaapi(params) do
    api_key = kaapi_config(:kaapi_api_key)

    credentials =
      []
      |> maybe_append_credential(:openai, params[:openai_api_key])
      |> maybe_append_credential(:google, params[:google_api_key])

    body = %{organization_name: params.organization_name, project_name: params.project_name}

    body =
      if credentials != [],
        do: Map.put(body, :credentials, credentials),
        else: body

    opts = [adapter: [recv_timeout: 30_000]]

    api_key
    |> client()
    |> Tesla.post("/api/v1/onboard", body, opts: opts)
    |> parse_kaapi_response()
  end

  @doc """
  Update credentials (e.g. google_api_key) for an existing Kaapi organization project.
  """
  @spec update_organization_credentials(map(), binary()) ::
          {:ok, map()} | {:error, map() | String.t()}
  def update_organization_credentials(params, org_api_key) do
    opts = [adapter: [recv_timeout: 30_000]]

    org_api_key
    |> client()
    |> Tesla.patch("/api/v1/credentials", params, opts: opts)
    |> parse_kaapi_response()
  end

  @doc """
  Calls Kaapi Responses API with the given payload.
  """
  @spec call_responses_api(map(), binary()) :: {:ok, any()} | {:error, any()}
  def call_responses_api(payload, org_api_key) do
    opts = [adapter: [recv_timeout: 60_000]]

    org_api_key
    |> client()
    |> Tesla.post("/api/v1/responses", payload, opts: opts)
    |> parse_kaapi_response()
  end

  @doc """
  Calls Kaapi Unified LLM API with the given payload.
  """
  @spec call_llm(map(), binary()) :: {:ok, any()} | {:error, any()}
  def call_llm(payload, org_api_key) do
    opts = [adapter: [recv_timeout: 60_000]]

    org_api_key
    |> client()
    |> Tesla.post("/api/v1/llm/call", payload, opts: opts)
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
    |> Tesla.patch("/api/v1/assistant/:assistant_id", body,
      opts: [path_params: [assistant_id: assistant_id]]
    )
    |> parse_kaapi_response()
  end

  @doc """
  Delete an assistant in Kaapi
  """
  @spec delete_assistant(binary(), binary()) :: {:ok, map()} | {:error, map() | String.t()}
  def delete_assistant(assistant_id, org_api_key) do
    org_api_key
    |> client()
    |> Tesla.delete("/api/v1/assistant/:assistant_id",
      opts: [path_params: [assistant_id: assistant_id]]
    )
    |> parse_kaapi_response()
  end

  @doc """
  Create a config in Kaapi (replaces old assistant creation)
  """
  @spec create_config(map(), binary()) :: {:ok, map()} | {:error, String.t()}
  def create_config(body, org_api_key) do
    org_api_key
    |> client()
    |> Tesla.post("/api/v1/configs/", body)
    |> parse_kaapi_response()
  end

  @doc """
  Create a config version in Kaapi.
  """
  @spec create_config_version(binary(), map(), binary()) :: {:ok, map()} | {:error, String.t()}
  def create_config_version(config_id, body, org_api_key) do
    org_api_key
    |> client()
    |> Tesla.post("/api/v1/configs/:config_id/versions", body,
      opts: [path_params: [config_id: config_id]]
    )
    |> parse_kaapi_response()
  end

  @doc """
  Create a collection in Kaapi.
  """
  @spec create_collection(map(), binary()) :: {:ok, map()} | {:error, map() | String.t()}
  def create_collection(params, org_api_key) do
    org_api_key
    |> client()
    |> Tesla.post("/api/v1/collections/", params)
    |> parse_kaapi_response()
  end

  @doc """
  Get the status of a collection in Kaapi.
  """
  @spec get_collection_status(String.t(), String.t()) ::
          {:ok, map()} | {:error, map() | String.t()}
  def get_collection_status(collection_job_id, org_api_key) do
    org_api_key
    |> client()
    |> Tesla.get("/api/v1/collections/jobs/#{collection_job_id}")
    |> parse_kaapi_response()
  end

  @doc """
  Delete a config in Kaapi
  """
  @spec delete_config(binary(), binary()) :: {:ok, map()} | {:error, map() | String.t()}
  def delete_config(uuid, org_api_key) do
    org_api_key
    |> client()
    |> Tesla.delete("/api/v1/configs/:uuid", opts: [path_params: [uuid: uuid]])
    |> parse_kaapi_response()
  end

  @doc """
  Ingests an assistant into the Kaapi platform.
  """
  @spec ingest_ai_assistants(non_neg_integer, String.t()) :: {:ok, any()} | {:error, String.t()}
  def ingest_ai_assistants(org_api_key, assistant_id) do
    opts = [adapter: [recv_timeout: 30_000], path_params: [assistant_id: assistant_id]]

    org_api_key
    |> client()
    |> Tesla.post("/api/v1/assistant/:assistant_id/ingest", %{}, opts: opts)
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
  Upload a document to Kaapi
  """
  @spec upload_document(map(), binary()) :: {:ok, map()} | {:error, any()}
  def upload_document(params, org_api_key) do
    content_type = MIME.from_path(params.filename)

    multipart =
      Tesla.Multipart.new()
      |> Tesla.Multipart.add_file(params.path,
        name: "src",
        filename: params.filename,
        headers: [{"content-type", content_type}]
      )
      |> add_optional_fields(params)

    org_api_key
    |> upload_client()
    |> Tesla.post("/api/v1/documents/", multipart)
    |> parse_kaapi_response()
  end

  @doc """
  Upload an evaluation dataset to Kaapi
  """
  @spec upload_evaluation_dataset(map(), String.t()) :: {:ok, map()} | {:error, any()}
  def upload_evaluation_dataset(params, org_api_key) do
    multipart =
      Tesla.Multipart.new()
      |> Tesla.Multipart.add_file(params.file.path,
        name: "file",
        filename: params.file.filename,
        headers: [{"content-type", params.file.content_type}]
      )
      |> Tesla.Multipart.add_field("dataset_name", params.dataset_name)
      |> Tesla.Multipart.add_field("duplication_factor", to_string(params.duplication_factor))

    opts = [adapter: [recv_timeout: 60_000]]

    org_api_key
    |> client()
    |> Tesla.post("/api/v1/evaluations/datasets", multipart, opts: opts)
    |> parse_kaapi_response()
  end

  @doc """
  Create an evaluation in Kaapi
  """
  @spec create_evaluation(map(), String.t()) :: {:ok, map()} | {:error, any()}
  def create_evaluation(params, org_api_key) do
    org_api_key
    |> client()
    |> Tesla.post("/api/v1/evaluations", params)
    |> parse_kaapi_response()
  end

  @doc """
  Get the current status of an evaluation from Kaapi (lightweight, used for polling).
  """
  @spec get_evaluation(non_neg_integer(), String.t()) :: {:ok, map()} | {:error, any()}
  def get_evaluation(evaluation_id, org_api_key) do
    org_api_key
    |> client()
    |> Tesla.get("/api/v1/evaluations/:evaluation_id",
      opts: [path_params: [evaluation_id: evaluation_id]]
    )
    |> parse_kaapi_response()
  end

  @doc """
  Get full scores for a completed evaluation from Kaapi (includes all evaluators via Langfuse).
  """
  @spec get_evaluation_scores(non_neg_integer(), String.t()) :: {:ok, map()} | {:error, any()}
  def get_evaluation_scores(evaluation_id, org_api_key) do
    org_api_key
    |> client()
    |> Tesla.get("/api/v1/evaluations/:evaluation_id?get_trace_info=true",
      opts: [path_params: [evaluation_id: evaluation_id]]
    )
    |> parse_kaapi_response()
  end

  @spec add_optional_fields(Tesla.Multipart.t(), map()) :: Tesla.Multipart.t()
  defp add_optional_fields(multipart, params) do
    [
      {:target_format, params[:target_format]},
      {:callback_url, params[:callback_url]}
    ]
    |> Enum.reduce(multipart, fn {field, value}, acc ->
      if value do
        Tesla.Multipart.add_field(acc, to_string(field), value)
      else
        acc
      end
    end)
  end

  @spec maybe_append_credential(list(), atom(), String.t() | nil) :: list()
  defp maybe_append_credential(credentials, _provider, nil), do: credentials

  defp maybe_append_credential(credentials, provider, api_key),
    do: credentials ++ [%{provider => %{api_key: api_key}}]

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

  defp upload_client(api_key) do
    case kaapi_config(:upload_adapter) do
      nil -> client(api_key)
      adapter -> client(api_key, adapter)
    end
  end

  defp kaapi_config, do: Application.fetch_env!(:glific, __MODULE__)
  defp kaapi_config(key), do: kaapi_config()[key]
end
