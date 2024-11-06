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

        Logger.error("Failed to fetch organization: #{inspect(body)}")
        {:error, "Failed to fetch organization due to #{extracted_message}"}

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
    encoded_customer_name = URI.encode(customer_name)
    erp_url = "#{@erp_base_url}/Customer/#{encoded_customer_name}"

    payload = %{
      "custom_chatbot_number" => registration.platform_details["phone"],
      "custom_gupshup_api_key" => registration.platform_details["api_key"],
      "custom_app_name" => registration.platform_details["app_name"],
      "custom_product_detail" => [
        %{
          "product" => "Glific",
          "service_type" => "SaaS",
          "billing_frequency" => registration.billing_frequency
        }
      ]
    }

    if registration.org_details["gstin"] not in [nil, ""] do
      Map.put(payload, "gstin", registration.org_details["gstin"])
      |> Map.put("gst_category", "Registered Regular")
    end

    case Tesla.put(@client, erp_url, payload, headers: headers()) do
      {:ok, %Tesla.Env{status: 200}} ->
        case create_or_update_address(registration, customer_name) do
          {:error, reason} ->
            {:error, reason}

          _ ->
            create_contact(registration, customer_name)
        end

      {:ok, %Tesla.Env{status: _status, body: body}} ->
        Logger.error("Failed to update organization: #{inspect(body)}")
        {:error, "Failed to update organization due to: #{body.exception}"}

      {:error, reason} ->
        Logger.error("Error updating organization: #{inspect(reason)}")
        {:error, "Error while updating organization"}
    end
  end

  defp create_or_update_address(registration, customer_name) do
    billing_exists? = address_exists?(customer_name, "Billing")
    permanent_exists? = address_exists?(customer_name, "Permanent/Registered")

    current_address = registration.org_details["current_address"]
    registered_address = registration.org_details["registered_address"]
    are_addresses_same = compare_addresses(current_address, registered_address)

    if billing_exists? do
      update_address(current_address, "Billing", customer_name)
    else
      create_address(current_address, "Billing", customer_name)
    end

    if not are_addresses_same do
      if permanent_exists? do
        update_address(registered_address, "Permanent/Registered", customer_name)
      else
        create_address(registered_address, "Permanent/Registered", customer_name)
      end
    end
  end

  defp address_exists?(customer_name, address_type) do
    encoded_customer_name = URI.encode(customer_name)
    erp_url = "#{@erp_base_url}/Address/#{encoded_customer_name}-#{address_type}"

    case Tesla.get(@client, erp_url, headers: headers()) do
      {:ok, %Tesla.Env{status: 200}} ->
        true

      {:ok, %Tesla.Env{status: 404}} ->
        false

      {:error, reason} ->
        Logger.error("Error checking address existence: #{inspect(reason)}")
        false
    end
  end

  defp create_address(address, address_type, customer_name) do
    erp_url = "#{@erp_base_url}/Address"
    payload = build_payload(address, address_type, customer_name)
    create_or_log_error(erp_url, payload)
  end

  defp update_address(address, address_type, customer_name) do
    encoded_customer_name = URI.encode(customer_name)
    erp_url = "#{@erp_base_url}/Address/#{encoded_customer_name}-#{address_type}"
    payload = build_payload(address, address_type, customer_name)
    update_or_log_error(erp_url, payload)
  end

  defp create_contact(registration, customer_name) do
    erp_url = "#{@erp_base_url}/Contact"

    payload = %{
      "custom_product" => [%{"product_type" => "Glific"}],
      "first_name" => registration.submitter["first_name"],
      "last_name" => registration.submitter["last_name"],
      "designation" => registration.submitter["designation"],
      "email_ids" => [%{"email_id" => registration.submitter["email"], "is_primary" => 1}],
      "custom_signing_authority" => [
        %{
          "name1" => registration.signing_authority["name"],
          "designation" => registration.signing_authority["designation"],
          "email" => registration.signing_authority["email"]
        }
      ],
      "custom_finance_team" => [
        %{
          "name1" => registration.finance_poc["name"],
          "designation" => registration.finance_poc["designation"],
          "email" => registration.finance_poc["email"],
          "phone" => registration.finance_poc["phone"]
        }
      ],
      "links" => [%{"link_doctype" => "Customer", "link_name" => customer_name}]
    }

    case Tesla.post(@client, erp_url, payload, headers: headers()) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: _status, body: body}} ->
        Logger.error("Failed to create contact: #{inspect(body)}")
        {:error, "Failed to create contact: #{body.exception}"}

      {:error, reason} ->
        Logger.error("Error creating contact: #{inspect(reason)}")
        {:error, "Error creating contact"}
    end
  end

  defp build_payload(address, address_type, customer_name) do
    %{
      "address_type" => address_type,
      "address_line1" => address["address_line1"],
      "address_line2" => address["address_line2"],
      "city" => address["city"],
      "state" => address["state"],
      "country" => address["country"],
      "pincode" => address["pincode"],
      "links" => [%{"link_doctype" => "Customer", "link_name" => customer_name}]
    }
  end

  defp create_or_log_error(url, payload) do
    case Tesla.post(@client, url, payload, headers: headers()) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: _status, body: body}} ->
        Logger.error("Failed to create address: #{inspect(body)}")
        {:error, "Failed to create address: #{body.exception}"}

      {:error, reason} ->
        Logger.error("Error creating address: #{inspect(reason)}")
        {:error, "Error creating address"}
    end
  end

  defp update_or_log_error(url, payload) do
    case Tesla.put(@client, url, payload, headers: headers()) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: _status, body: body}} ->
        Logger.error("Failed to update address: #{inspect(body)}")
        {:error, "Failed to update address: #{body.exception}"}

      {:error, reason} ->
        Logger.error("Error updating address: #{inspect(reason)}")
        {:error, "Error updating address"}
    end
  end

  defp compare_addresses(current_address, registered_address) do
    Enum.all?(Map.keys(current_address), fn key ->
      Map.get(current_address, key) == Map.get(registered_address, key)
    end)
  end
end
