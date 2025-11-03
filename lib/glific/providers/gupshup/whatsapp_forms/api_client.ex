defmodule Glific.Providers.Gupshup.WhatsappForms.ApiClient do
  @moduledoc """
  Module for managing WhatsApp Forms via Gupshup Partner API.

  This module provides functionality to create and manage WhatsApp forms
  using the Gupshup Partner API endpoints.
  """

  use Tesla
  alias Glific.Providers.Gupshup.PartnerAPI

  require Logger

  # client with runtime config (API key / base URL).

  @spec client(%{url: String.t(), header: list()}) :: Tesla.Client.t()
  defp client(opts) do
    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, opts.url},
        {Tesla.Middleware.Headers, opts.header},
        {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]},
        {Tesla.Middleware.Telemetry,
         metadata: %{provider: "gupshup_whatsapp_forms", sampling_scale: 10}}
      ] ++ Glific.get_tesla_retry_middleware()
    )
  end

  @doc false
  @spec publish_wa_form(String.t(), non_neg_integer()) ::
          {:ok, map()} | {:error, String.t()}
  def publish_wa_form(flow_id, organization_id) do
    with {:ok, %{partner_app_token: token}} <- PartnerAPI.get_partner_app_token(organization_id),
         url <- PartnerAPI.app_url!(organization_id),
         opts = %{
           url: url,
           header: [
             {"Content-Type", "application/json"},
             {"token", token}
           ]
         },
         {:ok, %Tesla.Env{} = response} <-
           Tesla.post(client(opts), "/flows/#{flow_id}/publish", %{}),
         {:ok, parsed} <- parse_response({:ok, response}) do
      {:ok, parsed}
    else
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
    case Jason.decode(body) do
      {:ok, %{"message" => message}} when is_binary(message) ->
        {:error, message}

      _ ->
        {:error, "Something went wrong"}
    end
  end
end
