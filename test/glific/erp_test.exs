defmodule Glific.ERPTest do
  @moduledoc """
  Tests for Glific.erp
  """

  use Glific.DataCase
  import Tesla.Mock

  alias Glific.ERP

  describe "fetch_organization_details/1" do
    test "returns organizations when the request is successful" do
      mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: %{
              "data" => [
                %{"name" => "Org1", "customer_name" => "Organization 1"}
              ]
            }
          }
      end)

      assert {:ok, %{"data" => [%{"customer_name" => "Organization 1", "name" => "Org1"}]}} =
               ERP.fetch_organization_detail("org1")
    end
  end

  test "returns error when the request contains an exception" do
    mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 404,
          body: %{
            _server_messages:
              "[\"{\\\"message\\\": \\\"Customer org1 not found\\\", \\\"title\\\": \\\"Message\\\", \\\"indicator\\\": \\\"red\\\", \\\"raise_exception\\\": 1, \\\"__frappe_exc_id\\\": \\\"xxx\\\"}\"]",
            exc_type: "DoesNotExistError"
          }
        }
    end)

    assert {:error, "Customer org1 not found"} =
             ERP.fetch_organization_detail("org1")
  end

  test "return is_valid true if the entry is updated in db" do
    # Mock the GET request for checking the address existence
    Tesla.Mock.mock(fn
      # Mock GET requests for checking address existence
      %{method: :get, url: url} when is_binary(url) ->
        if String.contains?(url, "/Address/") do
          %Tesla.Env{
            status: 404,
            body: %{"message" => "Address not found"}
          }
        else
          %Tesla.Env{status: 404, body: %{}}
        end

      # Mock PUT request for updating the organization
      %{method: :put, url: url} when is_binary(url) ->
        if String.contains?(url, "/Customer/") do
          %Tesla.Env{
            status: 200,
            body: %{"is_valid" => true}
          }
        else
          %Tesla.Env{status: 404, body: %{}}
        end

      # Mock POST requests for creating address and contact
      %{method: :post, url: url} when is_binary(url) ->
        cond do
          String.contains?(url, "/Address") ->
            %Tesla.Env{
              status: 200,
              body: %{"message" => "Address created"}
            }

          String.contains?(url, "/Contact") ->
            %Tesla.Env{
              status: 200,
              body: %{"message" => "Contact created"}
            }

          true ->
            %Tesla.Env{status: 404, body: %{}}
        end
    end)

    registration = %{
      org_details: %{
        "name" => "org1",
        "current_address" => %{
          "address_line1" => "123 Main St",
          "address_line2" => "Suite 100",
          "city" => "City",
          "state" => "State",
          "country" => "Country",
          "pincode" => "12345"
        },
        "registered_address" => %{
          "address_line1" => "456 Main St",
          "address_line2" => "Suite 200",
          "city" => "City",
          "state" => "State",
          "country" => "Country",
          "pincode" => "54321"
        }
      },
      platform_details: %{
        "phone" => "1234567890",
        "api_key" => "api-key",
        "app_name" => "GlificApp"
      },
      billing_frequency: "yearly",
      submitter: %{
        "first_name" => "John",
        "last_name" => "Doe",
        "designation" => "Manager",
        "email" => "john.doe@example.com"
      },
      signing_authority: %{
        "name" => "Jane Doe",
        "designation" => "Director",
        "email" => "jane.doe@example.com"
      },
      finance_poc: %{
        "name" => "Alice",
        "designation" => "Finance Head",
        "email" => "alice@example.com",
        "phone" => "9876543210"
      }
    }

    assert {:ok, _response} = ERP.update_organization(registration)
  end
end
