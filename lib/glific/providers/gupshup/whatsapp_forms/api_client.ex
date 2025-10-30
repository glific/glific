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

  @doc """
  Creates a WhatsApp form via Gupshup Partner API.
  """
  @spec create_whatsapp_form(map()) :: {:ok, map()} | {:error, any()}
  def create_whatsapp_form(params) do
    url = "#{get_url(params.organization_id)}/flows"
    headers = build_headers(params.organization_id)

    payload =
      %{
        name: params.name,
        categories: params.categories,
        flow_json: params.flow_json
      }
      |> Jason.encode!()

    post(url, payload, headers: headers) |> parse_response()
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
    {:ok, %{partner_app_token: partner_app_token}} =
      PartnerAPI.get_partner_app_token(organization_id)

    [
      {"Content-Type", "application/json"},
      {"token", partner_app_token}
    ]
  end

  defp parse_response({:ok, %Tesla.Env{status: status, body: body}})
       when status in 200..299 do
    resp_body = body |> Jason.decode!()
    {:ok, resp_body}
  end

  defp parse_response({:ok, %Tesla.Env{status: status, body: body}}) do
    case Jason.decode(body) do
      {:ok, %{"error" => error}} ->
        {:error, "API Error (#{status}): #{error["message"] || "Unknown error"}"}

      {:error, _} ->
        {:error, "Request failed with status #{status}"}
    end
  end
end
