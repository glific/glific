defmodule Glific.Providers.Maytapi.ApiClientTest do
  use Glific.DataCase

  alias Glific.Partners
  alias Glific.Providers.Maytapi.ApiClient
  alias Glific.Seeds.SeedsDev

  @phone_id 242
  @generic_error "WhatsApp couldn't complete this action right now. Please try again in a moment."

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

  defp mock_get(response), do: Tesla.Mock.mock(fn %{method: :get} -> response end)

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

    test "surfaces the reconnect hint when create fails because the phone isn't connected",
         %{organization_id: org_id} do
      mock_post(ok_body(%{"success" => false, "message" => "phone not connected"}))

      assert {:error, message} =
               ApiClient.create_group(org_id, @phone_id, %{name: "Group", numbers: []})

      assert message =~ "isn't connected"
    end

    test "surfaces an explicit WhatsApp-side message on an opaque create failure",
         %{organization_id: org_id} do
      mock_post(ok_body(%{"success" => false, "message" => "CreateGroup could not be completed"}))

      assert {:error, message} =
               ApiClient.create_group(org_id, @phone_id, %{name: "Group", numbers: []})

      assert message =~ "WhatsApp is temporarily blocking group creation"
    end

    test "surfaces an explicit WhatsApp-side message on an unexpected create response",
         %{organization_id: org_id} do
      mock_post(ok_body(%{"success" => true, "data" => %{}}))

      assert {:error, message} =
               ApiClient.create_group(org_id, @phone_id, %{name: "Group", numbers: []})

      assert message =~ "Couldn't create the WhatsApp group"
    end
  end

  describe "remove_group_member/3 response handling" do
    @payload %{conversation_id: "120363@g.us", number: "919425010449"}

    test "returns :ok on success", %{organization_id: org_id} do
      mock_post(ok_body(%{"success" => true}))
      assert :ok == ApiClient.remove_group_member(org_id, @payload, @phone_id)
    end

    test "maps a known Maytapi failure to a readable message", %{organization_id: org_id} do
      mock_post(ok_body(%{"success" => false, "message" => "NOT_A_PARTICIPANT"}))

      assert {:error, "That contact isn't a participant in this WhatsApp group."} ==
               ApiClient.remove_group_member(org_id, @payload, @phone_id)
    end

    test "falls back to a generic message for an unrecognised failure", %{organization_id: org_id} do
      mock_post(ok_body(%{"success" => false, "message" => "SOME_OBSCURE_CODE"}))

      assert {:error, @generic_error} ==
               ApiClient.remove_group_member(org_id, @payload, @phone_id)
    end

    test "returns a generic error when success is false without a message", %{
      organization_id: org_id
    } do
      mock_post(ok_body(%{"success" => false}))

      assert {:error, @generic_error} ==
               ApiClient.remove_group_member(org_id, @payload, @phone_id)
    end

    test "returns a generic error on an unexpected response", %{organization_id: org_id} do
      mock_post(ok_body(%{"unexpected" => "shape"}))

      assert {:error, @generic_error} ==
               ApiClient.remove_group_member(org_id, @payload, @phone_id)
    end

    test "returns the error on a transport failure", %{organization_id: org_id} do
      # :closed is not a retriable reason, so this resolves immediately.
      mock_post({:error, :closed})
      assert {:error, _reason} = ApiClient.remove_group_member(org_id, @payload, @phone_id)
    end
  end

  describe "instance-not-ready (W05) retry" do
    test "retries the 'Lib not loaded' (W05) response and succeeds on a later attempt", %{
      organization_id: org_id
    } do
      # W05 comes back as HTTP 200 with success:false, so the Tesla retry must
      # inspect the body. First call is not-ready, the retry succeeds.
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Tesla.Mock.mock(fn %{method: :post} ->
        attempt = Agent.get_and_update(counter, &{&1, &1 + 1})

        if attempt == 0,
          do: ok_body(%{"success" => false, "code" => "W05", "message" => "Lib not loaded"}),
          else: ok_body(%{"success" => true})
      end)

      payload = %{conversation_id: "120363@g.us", number: ["919425010449"]}
      assert :ok == ApiClient.add_group_member(org_id, payload, @phone_id)
      assert Agent.get(counter, & &1) >= 2
    end
  end

  describe "fetch_phone_screen/2 response handling" do
    test "returns a generic error when the non-PNG error body has no message", %{
      organization_id: org_id
    } do
      # A 200 that isn't a PNG is Maytapi's JSON error shape; without a message we
      # can't surface anything specific, so fall back to the generic error.
      mock_get(ok_body(%{"success" => false}))
      assert {:error, @generic_error} == ApiClient.fetch_phone_screen(org_id, @phone_id)
    end

    test "returns a generic error on a non-2xx response", %{organization_id: org_id} do
      mock_get({:ok, %Tesla.Env{status: 404, body: "not found"}})
      assert {:error, @generic_error} == ApiClient.fetch_phone_screen(org_id, @phone_id)
    end

    test "returns a generic error on a transport failure", %{organization_id: org_id} do
      # :closed is not a retriable reason, so this resolves immediately.
      mock_get({:error, :closed})
      assert {:error, @generic_error} == ApiClient.fetch_phone_screen(org_id, @phone_id)
    end
  end

  describe "list_wa_managed_phones/1 response handling" do
    test "returns a generic error on an unexpected (non-list) success body", %{
      organization_id: org_id
    } do
      # listPhones returns a JSON array on success; a `success: false` shape with
      # no message is neither a list nor a surfacable error → generic error.
      mock_get(ok_body(%{"success" => false}))
      assert {:error, @generic_error} == ApiClient.list_wa_managed_phones(org_id)
    end
  end
end
