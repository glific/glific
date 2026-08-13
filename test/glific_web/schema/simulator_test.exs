defmodule GlificWeb.Schema.SimulatorTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Fixtures,
    Messages,
    Partners,
    Repo
  }

  load_gql(:web_message, GlificWeb.Schema, "assets/gql/simulator/web_message.gql")

  @spec simulator_contact(non_neg_integer()) :: Contact.t()
  defp simulator_contact(organization_id) do
    {:ok, contact} =
      Repo.fetch_by(Contact, %{
        phone: Contacts.simulator_phone_prefix() <> "_1",
        organization_id: organization_id
      })

    contact
  end

  describe "simulatorWebMessage" do
    test "sends a TEXT message into the simulator contact's flow", %{staff: user} do
      contact = simulator_contact(1)

      result =
        auth_query_gql_by(:web_message, user,
          variables: %{
            "input" => %{
              "contactId" => contact.id,
              "type" => "TEXT",
              "body" => "hello simulator"
            }
          }
        )

      assert {:ok, query_data} = result
      message = get_in(query_data, [:data, "simulatorWebMessage", "message"])
      assert message["body"] == "hello simulator"
      assert message["channel"] == "web"
      assert is_nil(get_in(query_data, [:data, "simulatorWebMessage", "errors"]))

      [persisted | _] =
        Messages.list_conversation_messages(contact.id, "web", %{limit: 10, offset: 0})

      assert persisted.type == :text
      assert persisted.flow == :inbound
    end

    test "sends an IMAGE message with an already-hosted url", %{staff: user} do
      contact = simulator_contact(1)

      result =
        auth_query_gql_by(:web_message, user,
          variables: %{
            "input" => %{
              "contactId" => contact.id,
              "type" => "IMAGE",
              "url" => "http://example.com/x.jpg",
              "contentType" => "image/jpeg",
              "body" => "look at this"
            }
          }
        )

      assert {:ok, query_data} = result
      message = get_in(query_data, [:data, "simulatorWebMessage", "message"])
      assert message["type"] == "IMAGE"

      [persisted | _] =
        Messages.list_conversation_messages(contact.id, "web", %{limit: 10, offset: 0})

      assert persisted.type == :image
      refute is_nil(persisted.media_id)
    end

    test "sends a LOCATION message", %{staff: user} do
      contact = simulator_contact(1)

      result =
        auth_query_gql_by(:web_message, user,
          variables: %{
            "input" => %{
              "contactId" => contact.id,
              "type" => "LOCATION",
              "latitude" => 12.9,
              "longitude" => 77.5
            }
          }
        )

      assert {:ok, query_data} = result
      message = get_in(query_data, [:data, "simulatorWebMessage", "message"])
      assert message["type"] == "LOCATION"

      [persisted | _] =
        Messages.list_conversation_messages(contact.id, "web", %{limit: 10, offset: 0})

      assert persisted.type == :location

      location =
        Repo.get_by!(Glific.Contacts.Location, contact_id: contact.id, message_id: persisted.id)

      assert location.latitude == 12.9
      assert location.longitude == 77.5
    end

    test "answers an outbound :blocks message via BLOCKS_RESPONSE", %{staff: user} do
      contact = simulator_contact(1)

      {:ok, outbound} =
        Messages.create_message(%{
          body: "Reply with a course",
          type: :blocks,
          interactive_content: %{
            "type" => "blocks",
            "version" => 1,
            "component" => "glific/image-panel",
            "props" => %{
              "id" => "course",
              "options" => [
                %{"id" => "c1", "image" => "https://example.com/1.png", "label" => "A"}
              ]
            }
          },
          flow: :outbound,
          channel: "web",
          sender_id: Partners.organization_contact_id(1),
          contact_id: contact.id,
          receiver_id: contact.id,
          organization_id: 1,
          bsp_status: :delivered,
          status: :sent
        })

      result =
        auth_query_gql_by(:web_message, user,
          variables: %{
            "input" => %{
              "contactId" => contact.id,
              "type" => "BLOCKS_RESPONSE",
              "messageId" => outbound.id,
              "component" => "glific/image-panel",
              "values" => Jason.encode!(%{"course" => "c1"}),
              "summary" => "Picked A"
            }
          }
        )

      assert {:ok, query_data} = result
      message = get_in(query_data, [:data, "simulatorWebMessage", "message"])
      assert message["type"] == "BLOCKS_RESPONSE"
      assert message["body"] == "Picked A"

      [persisted | _] =
        Messages.list_conversation_messages(contact.id, "web", %{limit: 10, offset: 0})

      assert persisted.type == :blocks_response
      assert persisted.context_message_id == outbound.id
    end

    test "rejects a contact that is not a simulator contact", %{staff: user} do
      contact = Fixtures.contact_fixture(%{organization_id: 1})

      result =
        auth_query_gql_by(:web_message, user,
          variables: %{
            "input" => %{
              "contactId" => contact.id,
              "type" => "TEXT",
              "body" => "hello"
            }
          }
        )

      assert {:ok, query_data} = result
      assert %{errors: errors} = query_data
      assert errors != nil
    end

    # Belonging to another org, this contact simply isn't found by the org-scoped lookup — the
    # same "Resource not found" shape as every other by-id resolver, so it never even reaches
    # the simulator-contact check.
    test "rejects a simulator contact belonging to another organization", %{staff: user} do
      other_organization = Fixtures.organization_fixture()

      other_org_simulator_contact =
        Fixtures.contact_fixture(%{
          phone: Contacts.simulator_phone_prefix() <> "_other_org",
          organization_id: other_organization.id
        })

      result =
        auth_query_gql_by(:web_message, user,
          variables: %{
            "input" => %{
              "contactId" => other_org_simulator_contact.id,
              "type" => "TEXT",
              "body" => "hello"
            }
          }
        )

      assert {:ok, query_data} = result
      assert is_nil(get_in(query_data, [:data, "simulatorWebMessage", "message"]))
      errors = get_in(query_data, [:data, "simulatorWebMessage", "errors"])
      assert errors != nil and errors != []
    end
  end
end
