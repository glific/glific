defmodule Glific.Flows.NodeTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Contacts,
    Messages.Message,
    Seeds.SeedsDev,
    Settings
  }

  alias Glific.Flows.{
    Flow,
    FlowContext,
    Node
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_flows()
    :ok
  end

  test "process extracts the right values from json" do
    flow = %Flow{uuid: "Flow UUID 1"}

    json = %{
      "uuid" => "UUID 1",
      "actions" => [
        %{"uuid" => "UUID Act 1", "type" => "enter_flow", "flow" => %{"uuid" => "UUID 2"}},
        %{"uuid" => "UUID Act 2", "type" => "set_contact_language", "language" => "Hindi"}
      ],
      "exits" => [
        %{"uuid" => "UUID Exit 1", "destination_uuid" => "UUID Exit 2"},
        %{"uuid" => "UUID Exit 3", "destination_uuid" => nil}
      ]
    }

    {node, uuid_map} = Node.process(json, %{}, flow)

    assert node.uuid == "UUID 1"
    assert uuid_map[node.uuid] == {:node, node}
    assert length(node.actions) == 2
    assert length(node.exits) == 2

    # add a node with no actions but a router
    json = %{
      "uuid" => "UUID 123",
      "actions" => [],
      "exits" => [
        %{"uuid" => "UUID Exit 1", "destination_uuid" => "UUID Exit 2"},
        %{"uuid" => "UUID Exit 3", "destination_uuid" => nil}
      ],
      "router" => %{
        "operand" => "@input.text",
        "type" => "switch",
        "default_category_uuid" => "Default Cat UUID",
        "result_name" => "Language",
        "categories" => [
          %{"uuid" => "UUID Cat 1", "exit_uuid" => "UUID Cat 2", "name" => "Category Uno"},
          %{
            "uuid" => "Default Cat UUID",
            "exit_uuid" => "UUID Cat 2",
            "name" => "Default Category"
          }
        ],
        "cases" => [
          %{
            "uuid" => "UUID 1",
            "type" => "some type",
            "arguments" => [1, 2, 3],
            "category_uuid" => "UUID Cat 1"
          }
        ]
      }
    }

    {node, uuid_map} = Node.process(json, %{}, flow)

    assert node.uuid == "UUID 123"
    assert uuid_map[node.uuid] == {:node, node}
    assert Enum.empty?(node.actions)
    assert length(node.exits) == 2
    assert !is_nil(node.router)

    json = %{}
    assert_raise ArgumentError, fn -> Node.process(json, %{}, flow) end
  end

  test "execute a node having actions and without exit" do
    [flow | _tail] = Glific.Flows.list_flows()
    node_uuid_1 = Ecto.UUID.generate()

    json = %{
      "uuid" => node_uuid_1,
      "actions" => [
        %{
          "uuid" => "UUID Act 1",
          "type" => "set_contact_language",
          "language" => "English (United States)"
        },
        %{
          "uuid" => Ecto.UUID.generate(),
          "type" => "send_msg",
          "text" => "This is a test message"
        }
      ],
      "exits" => [
        %{"uuid" => "UUID Exit 1", "destination_uuid" => nil}
      ]
    }

    {node, uuid_map} = Node.process(json, %{}, flow)

    # create a simple flow context
    [contact | _] = Contacts.list_contacts(%{filter: %{name: "Default receiver"}})

    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: contact.id,
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        uuid_map: uuid_map
      })

    context = Repo.preload(context, :contact)

    message_stream = []

    # execute node
    assert {:ok, nil, []} = Node.execute(node, context, message_stream)

    # assert actions
    message =
      Message
      |> where([m], m.contact_id == ^contact.id)
      |> Ecto.Query.last()
      |> Repo.one()

    assert message.body == "This is a test message"

    [language | _] = Settings.list_languages(%{filter: %{label: "English (United States)"}})
    updated_contact = Contacts.get_contact!(contact.id)

    assert updated_contact.language_id == language.id
  end

  test "execute a node having router without cases should fail" do
    [flow | _tail] = Glific.Flows.list_flows()
    node_uuid_1 = Ecto.UUID.generate()

    json = %{
      "uuid" => node_uuid_1,
      "actions" => [
        %{
          "uuid" => "UUID Act 1",
          "type" => "set_contact_language",
          "language" => "English (United States)"
        }
      ],
      "exits" => [
        %{"uuid" => "UUID Exit 1", "destination_uuid" => nil}
      ],
      "router" => %{
        "operand" => "@input.text",
        "type" => "switch",
        "default_category_uuid" => "Default Cat UUID",
        "result_name" => "Language",
        "categories" => [
          %{
            "uuid" => "Default Cat UUID",
            "exit_uuid" => nil,
            "name" => "Default Category"
          }
        ],
        "cases" => []
      }
    }

    {node, uuid_map} = Node.process(json, %{}, flow)

    # create a simple flow context
    [contact | _] = Contacts.list_contacts(%{filter: %{name: "Default receiver"}})

    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: contact.id,
        flow_id: 1,
        uuid_map: uuid_map,
        flow_uuid: Ecto.UUID.generate()
      })

    context = Repo.preload(context, :contact)

    message_stream = ["completed"]

    # execute node
    assert_raise MatchError, fn ->
      {:ok, nil, []} = Node.execute(node, context, message_stream)
    end
  end
end
