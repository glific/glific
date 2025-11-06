defmodule Glific.Providers.Gupshup.WhatsappForms.ApiClient do
  @moduledoc """
  Module for managing WhatsApp Forms via Gupshup Partner API.

  This module provides functionality to create and manage WhatsApp forms
  using the Gupshup Partner API endpoints.
  """

  use Tesla
  alias Glific.Providers.Gupshup.PartnerAPI

  require Logger

  @spec client(keyword()) :: Tesla.Client.t()
  defp client(opts) do
    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, Keyword.fetch!(opts, :url)},
        {Tesla.Middleware.Headers, Keyword.fetch!(opts, :headers)},
        {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]},
        {Tesla.Middleware.Telemetry,
         metadata: %{provider: "gupshup_whatsapp_forms", sampling_scale: 10}}
      ] ++ Glific.get_tesla_retry_middleware()
    )
  end

  @doc """
  Creates a WhatsApp form via Gupshup Partner API.
  """
  @spec create_whatsapp_form(map()) :: {:ok, map()} | {:error, any()}
  def create_whatsapp_form(params) do
    url = PartnerAPI.app_url!(params.organization_id)
    headers = PartnerAPI.headers(:app_token, org_id: params.organization_id)

    payload =
      %{
        name: params.name,
        categories: Enum.map(params.categories, &String.upcase/1),
        flow_json: params.flow_json
      }

    client(url: url, headers: headers)
    |> Tesla.post("/flows", payload, headers: headers)
    |> parse_response()
  end

  @doc """
  Updates a WhatsApp form via Gupshup Partner API.
  """
  @spec update_whatsapp_form(String.t(), map()) :: {:ok, map()} | {:error, any()}
  def update_whatsapp_form(meta_flow_id, params) do
    url = "#{PartnerAPI.app_url!(params.organization_id)}/flows/#{meta_flow_id}"
    headers = PartnerAPI.headers(:app_token, org_id: params.organization_id)

    payload =
      %{
        name: params.name,
        categories: params.categories,
        flow_json: params.flow_json
      }
      |> Jason.encode!()

    put(url, payload, headers: headers) |> parse_response()
  end

  @spec parse_response({:ok, Tesla.Env.t()} | {:error, any()}) ::
          {:ok, map()} | {:error, String.t()}
  defp parse_response({:ok, %Tesla.Env{status: status, body: body}})
       when status in 200..299 do
    {:ok, body}
  end

  defp parse_response({:ok, %Tesla.Env{status: _status, body: body}}) do
    case body do
      %{:message => message} when is_binary(message) ->
        {:error, message}

      _ ->
        {:error, "Something went wrong"}
    end
  end
end
