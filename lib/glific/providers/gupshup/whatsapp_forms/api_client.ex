defmodule Glific.Providers.Gupshup.WhatsappForms.ApiClient do
  @moduledoc """
  Module for managing WhatsApp Forms via Gupshup Partner API.

  This module provides functionality to create and manage WhatsApp forms
  using the Gupshup Partner API endpoints.
  """

  use Tesla
  alias Glific.Providers.Gupshup.PartnerAPI

  require Logger

  @endpoint "https://partner.gupshup.io/partner/app/"

  defp client(organization_id) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, @endpoint},
      {Tesla.Middleware.Headers, build_headers(organization_id)},
      {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]},
      Tesla.Middleware.Telemetry
    ])
  end

  @spec get_url(non_neg_integer()) :: String.t()
  defp get_url(organization_id) do
    case PartnerAPI.app_id(organization_id) do
      {:ok, app_id} -> @endpoint <> "#{app_id}"
      {:error, reason} -> raise "Unable to get app_id: #{reason}"
    end
  end

  @spec build_headers(non_neg_integer()) :: list({String.t(), String.t()})
  defp build_headers(organization_id) do
    case PartnerAPI.get_partner_app_token(organization_id) do
      {:ok, %{partner_app_token: partner_app_token}} ->
        {:ok,
         [
           {"Content-Type", "application/json"},
           {"token", partner_app_token}
         ]}

      {:error, reason} ->
        Logger.error("Failed to get partner app token: #{inspect(reason)}")
        {:error, "Failed to get partner app token: #{reason}"}
    end
  end

  defp parse_response({:ok, %Tesla.Env{status: status, body: body}})
       when status in 200..299 do
    resp_body = body |> Jason.decode!()
    {:ok, resp_body}
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
