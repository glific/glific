defmodule Glific.ERPTest do
  @moduledoc """
  Tests for Glific.erp
  """

  use ExUnit.Case
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

    assert {:error, "Failed to fetch organization due to Customer org1 not found"} =
             ERP.fetch_organization_detail("org1")
  end
end
