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
        {:error, "Unexpected response from ERP due to  #{body.exception}"}

      {:error, reason} ->
        Logger.error("Failed to fetch organizations: #{inspect(reason)}")
        {:error, "Failed to fetch organizations"}
    end
  end

  @doc """
  Creates a new organization in the ERP system.
  """
  @spec create_address(map()) :: {:ok, map()} | {:error, String.t()}
  def create_organization(registration) do
    if Map.has_key?(registration, "erp_page_id") and not is_nil(registration["erp_page_id"]) do
      # If erp_page_id exists, update the organization
      case update_org_details(registration) do
        {:ok, response} ->
          handle_address_update(registration, response)

        {:error, update_error} ->
          {:error, "Failed to update organization: #{update_error}"}
      end
    else
      erp_url = "#{@erp_base_url}/Customer"

      payload = %{
        "customer_name" => registration.org_details["name"],
        "custom_chatbot_number" => registration.platform_details["phone"],
        "custom_gupshup_api_key" => registration.platform_details["api_key"],
        "custom_app_name" => registration.platform_details["app_name"],
        "customer_group" => "T4D"
      }

      case Tesla.post(@client, erp_url, payload, headers: headers()) do
        {:ok, %Tesla.Env{status: 200, body: response}} ->
          handle_address_update(registration, response)

        {:ok, %Tesla.Env{status: status, body: body}} ->
          Logger.error("Failed to create organization: status #{status}, body: #{inspect(body)}")
          {:error, "Failed to create organization in ERP due to: #{body.exception}"}

        {:error, reason} ->
          Logger.error("Error occurred while creating organization: #{inspect(reason)}")
          {:error, "Error while creating organization"}
      end
    end
  end

  defp handle_address_update(registration, response) do
    case create_address(registration) do
      {:ok, address_response} ->
        {:ok, Map.put(response, "address", address_response)}

      {:error, address_error} ->
        {:error, "Organization processed, but failed to update address: #{address_error}"}
    end
  end

  defp update_org_details(registration) do
    customer_name = registration.org_details["name"]
    erp_url = "#{@erp_base_url}/Customer/#{customer_name}"

    payload = %{
      "custom_chatbot_number" => registration.platform_details["phone"],
      "custom_gupshup_api_key" => registration.platform_details["api_key"],
      "custom_app_name" => registration.platform_details["app_name"]
    }

    case Tesla.put(@client, erp_url, payload, headers: headers()) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: 404, body: _}} ->
        {:error, "Customer not found for update"}

      {:error, reason} ->
        Logger.error("Error occurred while updating organization: #{inspect(reason)}")
        {:error, "Error updating organization"}
    end
  end

  defp create_address(registration) do
    customer_name = registration.org_details["name"]
    address_type = "Billing"
    erp_url = "#{@erp_base_url}/Address/#{customer_name}-#{address_type}"

    case Tesla.get(@client, erp_url, headers: headers()) do
      {:ok, %Tesla.Env{status: 200, body: _}} ->
        update_address(registration, customer_name)

      {:ok, %Tesla.Env{status: 404, body: _}} ->
        create_new_address(registration)

      {:error, reason} ->
        Logger.error("Error occurred while checking address existence: #{inspect(reason)}")
        {:error, "Error checking if address exists"}
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
        {:error, "Failed to update address in ERP"}

      {:error, reason} ->
        Logger.error("Error occurred while updating address: #{inspect(reason)}")
        {:error, "Error while updating address"}
    end
  end

  defp create_new_address(registration) do
    erp_url = "#{@erp_base_url}/Address"

    payload = build_address_payload(registration)

    case Tesla.post(@client, erp_url, payload, headers: headers()) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Failed to create address: status #{status}, body: #{inspect(body)}")
        {:error, "Failed to create address in ERP"}

      {:error, reason} ->
        Logger.error("Error occurred while creating address: #{inspect(reason)}")
        {:error, "Error while creating address"}
    end
  end

  defp build_address_payload(registration) do
    %{
      "address_title" => registration.org_details["name"],
      "address_type" => "Billing",
      "gst_category" => "Unregistered",
      "address_line1" => "123 Main Street",
      "address_line2" => "Suite 100",
      "city" => "Haldwani",
      "state" => "Uttarakhand",
      "country" => "India",
      "pincode" => "262402",
      "phone" => registration.platform_details["phone"],
      "email_id" => "contact@test-glific.org",
      "links" => [
        %{
          "link_doctype" => "Customer",
          "link_name" => registration.org_details["name"]
        }
      ]
    }
  end
end
