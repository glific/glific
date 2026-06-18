defmodule Glific.Providers.Maytapi.ApiClientTest do
  use Glific.DataCase

  alias Glific.Partners
  alias Glific.Providers.Maytapi.ApiClient
  alias Glific.Seeds.SeedsDev

  @phone_id 242

  setup do
    organization = SeedsDev.seed_organizations()

    Partners.create_credential(%{
      organization_id: organization.id,
      shortcode: "maytapi",
      keys: %{},
      secrets: %{
        "product_id" => "3fa22108-f464-41e5-81d9-d8a298854430",
        "token" => "f4f38e00-3a50-4892-99ce-a282fe24d041"
      },
      is_active: true
    })

    %{organization_id: organization.id}
  end

  defp mock_post(response), do: Tesla.Mock.mock(fn %{method: :post} -> response end)

  defp ok_body(map), do: {:ok, %Tesla.Env{status: 200, body: Jason.encode!(map)}}

  describe "create_group/3" do
    test "returns the new group's data on success", %{organization_id: org_id} do
      mock_post(
        ok_body(%{
          "success" => true,
          "data" => %{
            "id" => "120363@g.us",
            "participants" => ["919425010449@c.us"],
            "admins" => ["919425010449@c.us"]
          }
        })
      )

      assert {:ok,
              %{
                bsp_id: "120363@g.us",
                participants: ["919425010449@c.us"],
                admins: ["919425010449@c.us"]
              }} ==
               ApiClient.create_group(org_id, @phone_id, %{name: "Group", numbers: []})
    end

    test "returns the Maytapi message when create reports a failure", %{organization_id: org_id} do
      mock_post(ok_body(%{"success" => false, "message" => "phone not connected"}))

      assert {:error, "phone not connected"} ==
               ApiClient.create_group(org_id, @phone_id, %{name: "Group", numbers: []})
    end

    test "returns a generic error on an unexpected create response", %{organization_id: org_id} do
      mock_post(ok_body(%{"success" => true, "data" => %{}}))

      assert {:error, "Unexpected Maytapi create group response"} ==
               ApiClient.create_group(org_id, @phone_id, %{name: "Group", numbers: []})
    end
  end

  describe "remove_group_member/3 response handling" do
    @payload %{conversation_id: "120363@g.us", number: "919425010449"}

    test "returns :ok on success", %{organization_id: org_id} do
      mock_post(ok_body(%{"success" => true}))
      assert :ok == ApiClient.remove_group_member(org_id, @payload, @phone_id)
    end

    test "returns the Maytapi message on an application failure", %{organization_id: org_id} do
      mock_post(ok_body(%{"success" => false, "message" => "NOT_A_PARTICIPANT"}))

      assert {:error, "NOT_A_PARTICIPANT"} ==
               ApiClient.remove_group_member(org_id, @payload, @phone_id)
    end

    test "returns a generic error when success is false without a message", %{
      organization_id: org_id
    } do
      mock_post(ok_body(%{"success" => false}))

      assert {:error, "Maytapi request failed"} ==
               ApiClient.remove_group_member(org_id, @payload, @phone_id)
    end

    test "returns a generic error on an unexpected response", %{organization_id: org_id} do
      mock_post(ok_body(%{"unexpected" => "shape"}))

      assert {:error, "Unexpected Maytapi response"} ==
               ApiClient.remove_group_member(org_id, @payload, @phone_id)
    end

    test "returns the error on a transport failure", %{organization_id: org_id} do
      # :closed is not a retriable reason, so this resolves immediately.
      mock_post({:error, :closed})
      assert {:error, _reason} = ApiClient.remove_group_member(org_id, @payload, @phone_id)
    end
  end
end
