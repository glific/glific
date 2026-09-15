defmodule Glific.ERP do
  @moduledoc """
  ERP API integration utilities
  """

  require Logger
  use Tesla

  @client Tesla.client([
            {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]},
            Tesla.Middleware.FollowRedirects
          ])

  @spec headers() :: list()
  defp headers do
    erp_auth_token = get_erp_auth_token()

    [
      {"Content-Type", "application/json"},
      {"Authorization", "token #{erp_auth_token}"}
    ]
  end

  @spec get_erp_auth_token() :: String.t()
  defp get_erp_auth_token do
    api_key = Application.get_env(:glific, :ERP_API_KEY)
    secret = Application.get_env(:glific, :ERP_SECRET)
    "#{api_key}:#{secret}"
  end

  @spec get_base_url() :: String.t()
  defp get_base_url do
    Application.get_env(:glific, :ERP_ENDPOINT)
  end

  @doc """
  Fetches the erp_page_id of existing organization from ERP.
  """
  @spec fetch_organization_detail(String.t()) :: {:ok, map()} | {:error, String.t()}
  def fetch_organization_detail(org_name) do
    encoded_org_name = URI.encode(org_name)
    erp_url = "#{get_base_url()}/Customer/#{encoded_org_name}"

    case Tesla.get(@client, erp_url, headers: headers()) do
      {:ok, %Tesla.Env{status: 200, body: organization}} ->
        {:ok, organization}

      {:ok, %Tesla.Env{status: 404, body: body}} ->
        decoded_message =
          body._server_messages
          |> Jason.decode!()
          |> List.first()
          |> Jason.decode!()

        extracted_message = Map.get(decoded_message, "message")

        Logger.error("Failed to fetch organization: #{Glific.SafeLog.safe_inspect(body)}")
        {:error, "#{extracted_message}"}

      {:error, reason} ->
        Logger.error("Unexpected response: body: #{Glific.SafeLog.safe_inspect(reason)}")
        {:error, "Unexpected response from ERP due to #{Glific.SafeLog.safe_inspect(reason)}"}
    end
  end
end
