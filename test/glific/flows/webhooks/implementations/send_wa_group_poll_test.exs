defmodule Glific.Flows.Webhooks.SendWaGroupPollTest do
  @moduledoc """
  Unit tests for the SendWaGroupPoll webhook implementation.

  Tests the module directly via `call/2`, covering:
  - Happy path: valid wa_group, poll_uuid → {:ok, %{poll: poll_content}}
  - Missing wa_group field
  - Invalid poll_uuid (not a valid UUID)
  - Non-existent wa_managed_phone_id
  - Non-existent wa_group id
  - Non-existent poll_uuid
  """

  use Glific.DataCase, async: false

  alias Glific.Fixtures
  alias Glific.Flows.Webhooks.SendWaGroupPoll
  alias Glific.Partners
  alias Glific.Seeds.SeedsDev

  @ctx %{organization_id: 1}

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)

    Partners.create_credential(%{
      organization_id: 1,
      shortcode: "maytapi",
      keys: %{},
      secrets: %{
        "product_id" => "00000000-0000-0000-0000-000000000000",
        "token" => "11111111-1111-1111-1111-111111111111"
      },
      is_active: true
    })

    Partners.get_organization!(1) |> Partners.fill_cache()
    :ok
  end

  describe "call/2 - happy path" do
    test "returns {:ok, %{poll: poll_content}} when all records exist", %{
      organization_id: organization_id
    } do
      Tesla.Mock.mock(fn
        %{method: :post, url: "https://api.maytapi.com/api/" <> _} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "success" => true,
               "data" => %{
                 "chatId" => "120363238104@g.us",
                 "msgId" => "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d"
               }
             }
           }}
      end)

      wa_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})

      wa_group =
        Fixtures.wa_group_fixture(%{
          organization_id: organization_id,
          wa_managed_phone_id: wa_phone.id
        })

      poll = Fixtures.wa_poll_fixture(%{organization_id: organization_id})

      fields = %{
        "wa_group" => %{
          "id" => wa_group.id,
          "wa_managed_phone_id" => wa_phone.id
        },
        "poll_uuid" => poll.uuid
      }

      assert {:ok, %{poll: poll_content}} = SendWaGroupPoll.call(fields, @ctx)
      assert is_map(poll_content)
    end
  end

  describe "call/2 - validation failures" do
    test "returns {:error, 'wa_group is invalid'} when wa_group is missing" do
      assert {:error, "wa_group is invalid"} = SendWaGroupPoll.call(%{}, @ctx)
    end

    test "returns {:error, 'wa_group is invalid'} when wa_group is not a map" do
      fields = %{"wa_group" => "@wa_group", "poll_uuid" => Ecto.UUID.generate()}
      assert {:error, "wa_group is invalid"} = SendWaGroupPoll.call(fields, @ctx)
    end

    test "returns {:error, 'poll_uuid is invalid'} when poll_uuid is nil" do
      fields = %{"wa_group" => %{"id" => 1, "wa_managed_phone_id" => 1}}
      assert {:error, "poll_uuid is invalid"} = SendWaGroupPoll.call(fields, @ctx)
    end

    test "returns {:error, 'poll_uuid is invalid'} when poll_uuid is not a valid UUID" do
      fields = %{
        "wa_group" => %{"id" => 1, "wa_managed_phone_id" => 1},
        "poll_uuid" => "not-a-uuid"
      }

      assert {:error, "poll_uuid is invalid"} = SendWaGroupPoll.call(fields, @ctx)
    end
  end

  describe "call/2 - database lookup failures" do
    test "returns {:error, message} when wa_managed_phone_id is not found", %{
      organization_id: organization_id
    } do
      poll = Fixtures.wa_poll_fixture(%{organization_id: organization_id})

      fields = %{
        "wa_group" => %{
          "id" => 0,
          "wa_managed_phone_id" => 0
        },
        "poll_uuid" => poll.uuid
      }

      assert {:error, msg} = SendWaGroupPoll.call(fields, @ctx)
      assert is_binary(msg)
    end

    test "returns {:error, message} when wa_group id is not found", %{
      organization_id: organization_id
    } do
      wa_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})
      poll = Fixtures.wa_poll_fixture(%{organization_id: organization_id})

      fields = %{
        "wa_group" => %{
          "id" => 0,
          "wa_managed_phone_id" => wa_phone.id
        },
        "poll_uuid" => poll.uuid
      }

      assert {:error, msg} = SendWaGroupPoll.call(fields, @ctx)
      assert is_binary(msg)
    end

    test "returns {:error, message} when poll_uuid does not match any record", %{
      organization_id: organization_id
    } do
      wa_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})

      wa_group =
        Fixtures.wa_group_fixture(%{
          organization_id: organization_id,
          wa_managed_phone_id: wa_phone.id
        })

      nonexistent_uuid = Ecto.UUID.generate()

      fields = %{
        "wa_group" => %{
          "id" => wa_group.id,
          "wa_managed_phone_id" => wa_phone.id
        },
        "poll_uuid" => nonexistent_uuid
      }

      assert {:error, msg} = SendWaGroupPoll.call(fields, @ctx)
      assert is_binary(msg)
    end
  end
end
