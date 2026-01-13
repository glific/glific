defmodule Glific.Providers.Gupshup.WhatsappForms.ApiClient do
  @moduledoc """
  Module for managing WhatsApp Forms via Gupshup Partner API.

  This module provides functionality to create and manage WhatsApp forms
  using the Gupshup Partner API endpoints.
  """

  alias Glific.Providers.Gupshup.PartnerAPI
  alias Tesla.Multipart

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
        categories: Enum.map(params.categories, &String.upcase/1)
      }

    client(url: url, headers: headers)
    |> Tesla.post("/flows", payload)
    |> parse_response("create_whatsapp_form")
  end

  @doc """
  Updates a WhatsApp form via Gupshup Partner API.
  """
  @spec update_whatsapp_form(String.t(), map()) :: {:ok, map()} | {:error, any()}
  def update_whatsapp_form(meta_flow_id, params) do
    url = PartnerAPI.app_url!(params.organization_id)
    headers = PartnerAPI.headers(:app_token, org_id: params.organization_id)

    payload =
      %{
        name: params.name,
        categories: Enum.map(params.categories, &String.upcase/1)
      }

    opts = [adapter: [recv_timeout: 60_000]]

    client(url: url, headers: headers)
    |> Tesla.put("/flows/#{meta_flow_id}", payload, opts: opts)
    |> parse_response("update_whatsapp_form")
  end

  @doc """
  Updates the JSON definition of a WhatsApp form via Gupshup Partner API.
  """
  @spec update_whatsapp_form_json(map()) ::
          {:ok, map()} | {:error, String.t()}
  def update_whatsapp_form_json(form) do
    url = PartnerAPI.app_url!(form.organization_id)
    headers = PartnerAPI.headers(:app_token, org_id: form.organization_id)

    json_content = Jason.encode!(form.revision.definition)

    multipart =
      Multipart.new()
      |> Multipart.add_file_content(json_content, "flow.json",
        name: "file",
        headers: [{"content-type", "application/json"}]
      )

    client(url: url, headers: headers)
    |> Tesla.put("/flows/#{form.meta_flow_id}/assets", multipart)
    |> parse_response("update_whatsapp_form_json")
  end

  @doc """
  Publishes a WhatsApp Flow Form for a given organization via the Gupshup Partner API.
  """
  @spec publish_whatsapp_form(String.t(), non_neg_integer()) ::
          {:ok, map()} | {:error, String.t()}
  def publish_whatsapp_form(flow_id, organization_id) do
    url = PartnerAPI.app_url!(organization_id)
    headers = PartnerAPI.headers(:app_token, org_id: organization_id)

    Tesla.post(client(url: url, headers: headers), "/flows/#{flow_id}/publish", %{})
    |> parse_response("publish_whatsapp_form")
  end

  @spec parse_response(
          {:ok, Tesla.Env.t()} | {:error, any()},
          String.t()
        ) :: {:ok, map()} | {:error, String.t()}
  defp parse_response({:ok, %Tesla.Env{status: status, body: body}}, _action)
       when status in 200..299 do
    {:ok, body}
  end

  defp parse_response({:ok, %Tesla.Env{status: status, body: body}}, action) do
    Logger.error("""
    [Gupshup WhatsAppForms API Error]
    Action: #{action}
    Status: #{status}
    Response Body: #{inspect(body)}
    """)

    {:error, body}
  end

  defp parse_response({:error, reason}, action) do
    Logger.error("""
    [Gupshup WhatsAppForms API Request Failed]
    Action: #{action}
    Reason: #{inspect(reason)}
    """)

    {:error, inspect(reason)}
  end
end
