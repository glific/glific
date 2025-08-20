defmodule Glific.ThirdParty.Kaapi.ApiClient do
  @moduledoc """
  API Client for Kaapi Integration.
  """

  use Tesla
  require Logger

  # client with runtime config (API key / base URL).
  defp client do
    base_url = kaapi_config(:kaapi_endpoint)
    api_key = kaapi_config(:kaapi_api_key)

    Tesla.client([
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.Headers, headers(api_key)},
      {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]},
      Tesla.Middleware.Telemetry
    ])
  end

  @doc """
  Onboard NGOs to kaapi
  """
  @spec onboard_to_kaapi(map()) :: {:ok, %{api_key: String.t()}} | {:error, String.t()}
  def onboard_to_kaapi(params) do
    body = %{
      organization_name: params.organization_name,
      project_name: params.project_name,
      user_name: params.user_name
    }

    client()
    |> Tesla.post("/api/v1/onboard", body)
    |> parse_onboard_response()
  end

  @doc """
  Create an assistant in Kaapi
  """
  @spec create_assistant(map(), non_neg_integer()) :: {:ok, map()} | {:error, String.t()}
  def create_assistant(params, org_id) do
    body =
      %{
        name: params.name,
        model: params.model,
        assistant_id: params.id,
        instructions: "you are a helpful asssitant",
        organization_id: org_id
      }

    request(:post, "/api/v1/assistant/", body) |> IO.inspect()
  end

  @doc """
  Update an assistant in Kaapi
  """
  @spec update_assistant(map(), non_neg_integer()) :: {:ok, map()} | {:error, String.t()}
  def update_assistant(params, org_id) do
    body = %{
      name: params.name,
      model: params.model,
      instructions: Map.get(params, :instructions),
      temperature: Map.get(params, :temperature),
      organization_id: org_id,
      vector_store_ids_add:
        get_in(params, [:tool_resources, :file_search, :vector_store_ids]) || []
    }

    request(:patch, "/api/v1/assistant/#{params.id}", body)
  end

  @spec request(:post | :patch, String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  defp request(method, path, body) do
    resp =
      case method do
        :post -> client() |> Tesla.post(path, body) |> IO.inspect()
        :patch -> client() |> Tesla.patch(path, body)
      end

    parse_assistant_response(resp)
  end

  @spec parse_onboard_response(Tesla.Env.result()) ::
          {:ok, %{api_key: String.t()}} | {:error, String.t()}
  defp parse_onboard_response({:ok, %Tesla.Env{status: status, body: %{api_key: api_key}}})
       when status in 200..299 and is_binary(api_key) do
    {:ok, %{api_key: api_key}}
  end

  defp parse_onboard_response({:ok, %Tesla.Env{status: status, body: %{error: msg}}})
       when is_binary(msg) do
    Logger.error("KAAPI onboard error (status=#{status}): #{inspect(msg)}")
    {:error, msg}
  end

  defp parse_onboard_response({:ok, %Tesla.Env{status: status, body: body}})
       when status >= 400 do
    msg =
      case body do
        %{error: e} when is_binary(e) -> e
        _ -> "HTTP #{status}"
      end

    Logger.error("KAAPI onboard HTTP error (status=#{status}): #{inspect(msg)}")
    {:error, msg}
  end

  defp parse_onboard_response({:error, reason}) do
    Logger.error("KAAPI onboard transport error: #{inspect(reason)}")
    {:error, "API request failed"}
  end

  @spec parse_assistant_response(Tesla.Env.result()) :: {:ok, map()} | {:error, String.t()}
  defp parse_assistant_response(
         {:ok, %Tesla.Env{status: status, body: %{success: true, error: nil, data: data}}}
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

  defp parse_assistant_response({:ok, %Tesla.Env{status: status, body: %{error: msg}}})
       when is_binary(msg) do
    Logger.error("KAAPI assistant API error (status=#{status}): #{inspect(msg)}")
    {:error, msg}
  end

  defp parse_assistant_response({:ok, %Tesla.Env{status: status, body: body}})
       when status >= 400 do
    msg =
      case body do
        %{error: e} when is_binary(e) -> e
        _ -> "HTTP #{status}"
      end

    Logger.error("KAAPI assistant HTTP error (status=#{status}): #{inspect(msg)}")
    {:error, msg}
  end

  defp parse_assistant_response({:error, reason}) do
    Logger.error("KAAPI assistant transport error: #{inspect(reason)}")
    {:error, "API request failed"}
  end

  defp kaapi_config, do: Application.fetch_env!(:glific, __MODULE__)
  defp kaapi_config(key), do: kaapi_config()[key]

  defp headers(api_key) do
    [
      {"X-API-KEY", api_key},
      {"content-type", "application/json"}
    ]
  end
end
