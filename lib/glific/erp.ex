defmodule Glific.ERP do
  @moduledoc """
  ERP API integration utilities
  """

  require Logger
  use Tesla

  @erp_base_url "https://t4d-erp.frappe.cloud/api/resource"

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

  @doc """
  Fetches the erp_page_id of existing organization from ERP.
  """
  @spec fetch_organization_detail(String.t()) :: {:ok, map()} | {:error, String.t()}
  def fetch_organization_detail(org_name) do
    encoded_org_name = URI.encode(org_name)
    erp_url = "#{@erp_base_url}/Customer/#{encoded_org_name}"

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

        Logger.error("Failed to fetch organizations: #{inspect(body)}")
        {:error, "Failed to fetch organizations due to #{extracted_message}"}

      {:error, reason} ->
        Logger.error("Unexpected response: body: #{inspect(reason)}")
        {:error, "Unexpected response from ERP due to #{inspect(reason)}"}
    end
  end

  @doc """
  update the existing organization in the ERP system.
  """
  @spec update_organization(map()) :: {:ok, map()} | {:error, String.t()}
  def update_organization(registration) do
    customer_name = registration.org_details["name"]
    erp_url = "#{@erp_base_url}/Customer/#{customer_name}"

    payload = %{
      "custom_chatbot_number" => registration.platform_details["phone"],
      "custom_gupshup_api_key" => registration.platform_details["api_key"],
      "custom_app_name" => registration.platform_details["app_name"],
      "custom_product_detail" => [
        %{
          "product" => "Glific",
          "service_type" => "SaaS",
          "billing_frequency" => registration.billing_frequency,
        }
      ]
    }

    if registration.org_details["gstin"] != nil and registration.org_details["gstin"] != "" do
      Map.put(payload, "gstin", registration.org_details["gstin"])
      |> Map.put("gst_category", "Registered Regular")
    end

    case Tesla.put(@client, erp_url, payload, headers: headers()) do
      {:ok, %Tesla.Env{status: 200, body: _response}} ->
        update_address(registration, customer_name)

      {:ok, %Tesla.Env{status: _status, body: body}} ->
        Logger.error("Failed to update organization due to: #{inspect(body)}")
        {:error, "Failed to update organization in ERP due to: #{body.exception}"}

      {:error, reason} ->
        Logger.error("Error occurred while updating organization: #{inspect(reason)}")
        {:error, "Error while updating organization"}
    end
  end

  defp update_address(registration, customer_name) do
    address_type = "Billing"
    erp_url = "#{@erp_base_url}/Address/#{customer_name}-#{address_type}"

    payload = build_address_payload(registration)

    case Tesla.put(@client, erp_url, payload, headers: headers()) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Failed to update address: status #{status}, body: #{inspect(body)}")
        {:error, "Failed to update address in ERP #{body.exception}"}

      {:error, reason} ->
        Logger.error("Error occurred while updating address: #{inspect(reason)}")
        {:error, "Error while updating address"}
    end
  end

  defp build_address_payload(registration) do
    registered_address = registration.org_details["registered_address"]

    %{
      "address_title" => registered_address["address_title"],
      "address_type" => registered_address["address_type"],
      "address_line1" => registered_address["address_line1"],
      "address_line2" => registered_address["address_line2"],
      "city" => registered_address["city"],
      "state" => registered_address["state"],
      "country" => registered_address["country"],
      "pincode" => registered_address["pincode"],
      "links" => [
        %{
          "link_doctype" => "Customer",
          "link_name" => registration.org_details["name"]
        }
      ]
    }
  end
end
