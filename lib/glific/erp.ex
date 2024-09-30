defmodule Glific.ERP do
  @moduledoc """
  ERP API integration utilities for fetching organization data.
  """

  require Logger
  use Tesla

  @erp_base_url "https://t4d-erp.frappe.cloud/api/resource"
  @erp_auth_token "xx"

  # Tesla client with middleware
  @client Tesla.client([
            {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]},
            Tesla.Middleware.FollowRedirects
          ])

  @spec headers() :: list()
  defp headers do
    [
      {"Content-Type", "application/json"},
      {"Authorization", "token #{@erp_auth_token}"}
    ]
  end

  @doc """
  Fetches the list of existing organizations from ERP.
  """
  @spec fetch_organizations() :: {:ok, map()} | {:error, String.t()}
  def fetch_organizations do
    query_params = %{
      "fields" => ~s(["name", "customer_name"]),
      "limit_page_length" => "0"
    }

    erp_url = "#{@erp_base_url}/Customer?#{URI.encode_query(query_params)}"

    case Tesla.get(@client, erp_url, headers: headers()) do
      {:ok, %Tesla.Env{status: 200, body: organizations}} ->
        {:ok, organizations}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Unexpected response: status #{status}, body: #{inspect(body)}")
        {:error, "Unexpected response from ERP: Status #{status}, Body: #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("Failed to fetch organizations: #{inspect(reason)}")
        {:error, "Failed to fetch organizations"}
    end
  end
end
