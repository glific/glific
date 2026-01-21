defmodule Glific.ERP do
  @moduledoc """
  ERP API integration utilities
  """

  require Logger
  use Tesla

  @erp_base_url Application.compile_env(:glific, :ERP_ENDPOINT)

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
        {:error, "#{extracted_message}"}

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
    gstin = registration.org_details["gstin"]

    payload = %{
      "custom_chatbot_number" => registration.platform_details["phone"],
      "custom_status" => "Active",
      "custom_product_detail" => [
        %{
          "product" => "Glific",
          "service_type" => "SaaS",
          "billing_frequency" => registration.billing_frequency,
          "subscription_start_date" =>
            DateTime.utc_now() |> DateTime.to_date() |> Date.to_iso8601()
        }
      ]
    }

    payload =
      if gstin in ["", nil] do
        payload
      else
        Map.put(payload, "gstin", gstin)
        |> Map.put("gst_category", "Registered Regular")
      end

    case Tesla.put(@client, erp_url, payload, headers: headers()) do
      {:ok, %Tesla.Env{status: 200}} ->
        case create_or_update_address(registration, customer_name) do
          {:error, reason} ->
            {:error, reason}

          {:ok, _} ->
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

  @spec create_or_update_address(map(), String.t()) :: {:ok, any} | {:error, String.t()}
  defp create_or_update_address(registration, customer_name) do
    current_address = registration.org_details["current_address"]
    registered_address = registration.org_details["registered_address"]
    are_addresses_same = compare_addresses(current_address, registered_address)

    with {:ok, _billing} <-
           do_create_or_update_address(current_address, "Billing", customer_name) do
      handle_registered_address(are_addresses_same, registered_address, customer_name)
    end
  end

  @spec handle_registered_address(boolean(), map(), String.t()) ::
          {:ok, map()} | {:error, String.t()}
  defp handle_registered_address(false, registered_address, customer_name),
    do: do_create_or_update_address(registered_address, "Permanent/Registered", customer_name)

  defp handle_registered_address(true, _registered_address, _customer_name), do: {:ok, nil}

  @spec do_create_or_update_address(map(), String.t(), String.t()) ::
          {:ok, map()} | {:error, String.t()}
  defp do_create_or_update_address(address, type, customer_name) do
    if address_exists?(customer_name, type) do
      update_address(address, type, customer_name)
    else
      create_address(address, type, customer_name)
    end
  end

  @spec address_exists?(String.t(), String.t()) :: boolean()
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

  @spec create_address(map(), String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  defp create_address(address, address_type, customer_name) do
    erp_url = "#{@erp_base_url}/Address"
    payload = build_payload(address, address_type, customer_name)
    do_create_address(erp_url, payload)
  end

  @spec update_address(map(), String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  defp update_address(address, address_type, customer_name) do
    encoded_customer_name = URI.encode(customer_name)
    erp_url = "#{@erp_base_url}/Address/#{encoded_customer_name}-#{address_type}"
    payload = build_payload(address, address_type, customer_name)
    do_update_address(erp_url, payload)
  end

  @spec create_contact(map(), String.t()) :: {:ok, map()} | {:error, String.t()}
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

  @spec build_payload(map(), String.t(), String.t()) :: map()
  defp build_payload(address, address_type, customer_name) do
    %{
      "address_type" => address_type,
      "address_line1" => address["address_line1"],
      "address_line2" => address["address_line2"],
      "city" => capitalize_words(address["city"]),
      "state" => capitalize_words(address["state"]),
      "country" => capitalize_words(address["country"]),
      "pincode" => address["pincode"],
      "links" => [%{"link_doctype" => "Customer", "link_name" => customer_name}]
    }
  end

  @spec do_create_address(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  defp do_create_address(url, payload) do
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

  @spec do_update_address(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  defp do_update_address(url, payload) do
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

  @spec compare_addresses(map(), map()) :: boolean()
  defp compare_addresses(current_address, registered_address) do
    Enum.all?(Map.keys(current_address), fn key ->
      Map.get(current_address, key) == Map.get(registered_address, key)
    end)
  end

  @spec capitalize_words(String.t()) :: String.t()
  defp capitalize_words(string) do
    String.split(string, " ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
