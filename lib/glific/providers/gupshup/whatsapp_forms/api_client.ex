defmodule Glific.Providers.Gupshup.WhatsappForms.ApiClient do
  @moduledoc """
  Module for managing WhatsApp Forms via Gupshup Partner API.

  This module provides functionality to create and manage WhatsApp forms
  using the Gupshup Partner API endpoints.
  """

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
  Publishes a WhatsApp Flow Form for a given organization via the Gupshup Partner API.
  """
  @spec publish_wa_form(String.t(), non_neg_integer()) ::
          {:ok, map()} | {:error, String.t()}
  def publish_wa_form(flow_id, organization_id) do
    url = PartnerAPI.app_url!(organization_id)
    headers = PartnerAPI.headers(:app_token, org_id: organization_id)

    case Tesla.post(client(url: url, headers: headers), "/flows/#{flow_id}/publish", %{}) do
      {:ok, %Tesla.Env{} = response} -> parse_response({:ok, response})
      {:error, reason} -> {:error, reason}
    end
  end

  @spec parse_response({:ok, Tesla.Env.t()} | {:error, any()}) ::
          {:ok, map()} | {:error, String.t()}
  defp parse_response({:ok, %Tesla.Env{status: status, body: body}})
       when status in 200..299 do
    {:ok, body}
  end

  defp parse_response({:ok, %Tesla.Env{status: _status, body: body}}) do
    {:error, body}
  end
end
