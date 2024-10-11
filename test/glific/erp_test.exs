defmodule Glific.ERPTest do
  @moduledoc """
  Tests for Glific.erp
  """

  use ExUnit.Case
  import Tesla.Mock

  alias Glific.ERP

  describe "fetch_organizations/0" do
    test "returns organizations when the request is successful" do
      mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: %{
              "data" => [
                %{"name" => "Org1", "customer_name" => "Organization 1"},
                %{"name" => "Org2", "customer_name" => "Organization 2"}
              ]
            }
          }
      end)

      assert {:ok, %{"data" => organizations}} = ERP.fetch_organizations()
      assert length(organizations) == 2
      assert %{"name" => "Org1", "customer_name" => "Organization 1"} = hd(organizations)
    end
  end

  test "returns error when the request contains an exception" do
    mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 401,
          body: %{
            exception: "AuthenticationError"
          }
        }
    end)

    assert {:error, _} = ERP.fetch_organizations()
  end
end
