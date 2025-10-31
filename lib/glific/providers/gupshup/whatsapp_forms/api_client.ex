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

  defp client(opts) do
    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, @endpoint},
        {Tesla.Middleware.Headers, PartnerAPI.headers(:app_token, opts)},
        {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]},
        {Tesla.Middleware.Telemetry,
         metadata: %{provider: "gupshup_whatsapp_forms", sampling_scale: 10}}
      ] ++ Glific.get_tesla_retry_middleware()
    )
  end

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

  @spec get_tesla_middlewares :: list()
  defp get_tesla_middlewares do
    [{Tesla.Middleware.Telemetry, metadata: %{provider: "Gupshup", sampling_scale: 10}}] ++
      Glific.get_tesla_retry_middleware()
  end
end
