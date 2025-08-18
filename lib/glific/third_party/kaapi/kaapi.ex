defmodule Glific.ThirdParty.Kaapi do
  @moduledoc """
  Kaapi Integration Module
  """
  require Logger

  use Tesla
  plug(Tesla.Middleware.JSON, engine_opts: [keys: :atoms])

  @doc """
  Onboard NGOs to kaapi
  """
  @spec onboard_to_kaapi(map()) :: {:ok, %{api_key: String.t()}} | {:error, String.t()}
  def onboard_to_kaapi(params) do
    kaapi_url = Application.fetch_env!(:glific, :kaapi_endpoint)
    url = kaapi_url <> "api/v1/onboard"

    payload = %{
      organization_name: params.organization_name,
      project_name: params.project_name,
      email: params.email,
      password: params.password,
      user_name: params.user_name
    }

    key = Application.fetch_env!(:glific, :kaapi_api_key)

    post(
      url,
      Jason.encode!(payload),
      headers: [
        {"X-API-KEY", key},
        {"Content-Type", "application/json"}
      ]
    )
    |> parse_kaapi_response()
  end

  @spec parse_kaapi_response(Tesla.Env.result()) ::
          {:ok, %{api_key: String.t()}} | {:error, String.t()}
  defp parse_kaapi_response({:ok, %Tesla.Env{status: status, body: %{api_key: api_key}}})
       when status in 200..299 and is_binary(api_key) do
    {:ok, %{api_key: api_key}}
  end

  defp parse_kaapi_response({:ok, %Tesla.Env{body: %{error: error_msg}}})
       when is_binary(error_msg) do
    Logger.error("KAAPI API error: #{inspect(error_msg)}")
    {:error, error_msg}
  end

  defp parse_kaapi_response({:ok, %Tesla.Env{status: status, body: body}})
       when status >= 400 do
    msg =
      case body do
        %{error: e} when is_binary(e) -> e
        _ -> "HTTP #{status}"
      end

    Logger.error("KAAPI API HTTP error: #{inspect(msg)}")
    {:error, msg}
  end

  defp parse_kaapi_response({:error, message}) do
    Logger.error("KAAPI API transport error: #{inspect(message)}")
    {:error, "API request failed"}
  end
end
