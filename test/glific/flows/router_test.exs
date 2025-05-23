defmodule Glific.Flows.RouterTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Fixtures,
    Groups,
    Messages
  }

  alias Faker.Phone

  alias Glific.Flows.{
    Flow,
    FlowContext,
    Node,
    Router
  }

  @valid_attrs %{
    flow_id: 1,
    flow_uuid: Ecto.UUID.generate(),
    uuid_map: %{},
    node_uuid: Ecto.UUID.generate()
  }

  def flow_context_fixture(attrs \\ %{}) do
    contact = Fixtures.contact_fixture()

    {:ok, flow_context} =
      attrs
      |> Map.put(:contact_id, contact.id)
      |> Map.put(:organization_id, contact.organization_id)
      |> Enum.into(@valid_attrs)
      |> FlowContext.create_flow_context()

    flow_context
    |> Repo.preload(:contact)
    |> Repo.preload(:flow)
  end

  test "process extracts the right values from json" do
    json = %{
      "operand" => "@input.text",
      "type" => "switch",
      "default_category_uuid" => "Default Cat UUID",
      "result_name" => "Language",
      "categories" => [
        %{"uuid" => "UUID Cat 1", "exit_uuid" => "UUID Cat 2", "name" => "Category Uno"},
        %{"uuid" => "Default Cat UUID", "exit_uuid" => "UUID Cat 2", "name" => "Default Category"}
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

    node = %Node{uuid: "Node UUID"}
    {router, _uuid_map} = Router.process(json, %{}, node)

    assert router.default_category_uuid == "Default Cat UUID"
    assert router.result_name == "Language"
    assert router.type == "switch"
    assert length(router.categories) == 2
    assert length(router.cases) == 1

    # ensure that not sending either of the required fields, raises an error
    # no categories
    json = %{
      "operand" => "@input.text",
      "type" => "switch",
      "result_name" => "Language",
      "cases" => [
        %{
          "uuid" => "UUID 1",
          "type" => "some type",
          "arguments" => [1, 2, 3],
          "category_uuid" => "UUID Cat 1"
        }
      ]
    }

    assert_raise ArgumentError, fn -> Router.process(json, %{}, node) end

    # no type
    json = %{
      "operand" => "@input.text",
      "default_category_uuid" => "Default Cat UUID",
      "result_name" => "Language",
      "categories" => [
        %{"uuid" => "UUID Cat 1", "exit_uuid" => "UUID Cat 2", "name" => "Category Uno"},
        %{"uuid" => "Default Cat UUID", "exit_uuid" => "UUID Cat 2", "name" => "Default Category"}
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

    assert_raise ArgumentError, fn -> Router.process(json, %{}, node) end

    json = %{}
    assert_raise ArgumentError, fn -> Router.process(json, %{}, node) end
  end

  test "router execution when no messages are sent" do
    result = Router.execute(nil, nil, [])

    assert result == {:ok, nil, []}
  end

  test "router execution with type not equal to switch" do
    router = %Router{type: "No type"}

    message = Messages.create_temp_message(Fixtures.get_org_id(), "Random Input")
    assert_raise UndefinedFunctionError, fn -> Router.execute(router, nil, [message]) end
  end

  test "router with switch and one case, category" do
    flow = %Flow{uuid: "Flow UUID 1", id: 1}
    exit_uuid = Ecto.UUID.generate()
    uuid_map = %{}

    json = %{
      "uuid" => "Node UUID",
      "actions" => [],
      "exits" => [
        %{"uuid" => exit_uuid, "destination_uuid" => nil}
      ]
    }

    {node, uuid_map} = Node.process(json, uuid_map, flow)

    json = %{
      "operand" => "@input.text",
      "type" => "switch",
      "default_category_uuid" => "Default Cat UUID",
      "result_name" => "Language",
      "categories" => [
        %{"uuid" => "UUID Cat 1", "exit_uuid" => exit_uuid, "name" => "Category Uno"},
        %{
          "uuid" => "Default Cat UUID",
          "exit_uuid" => exit_uuid,
          "name" => "Default Category"
        }
      ],
      "cases" => [
        %{
          "uuid" => "UUID 1",
          "type" => "has_number_eq",
          "arguments" => ["23"],
          "category_uuid" => "UUID Cat 1"
        }
      ]
    }

    {router, uuid_map} = Router.process(json, uuid_map, node)

    # create a simple flow context
    context = flow_context_fixture(%{uuid_map: uuid_map})

    message = Messages.create_temp_message(Fixtures.get_org_id(), "23")
    result = Router.execute(router, context, [message])

    # we send it to a null node. lets ensure we get the right values
    assert result == {:ok, nil, []}

    # need to recreate the context, since we blew it away when the previous
    context = flow_context_fixture(%{uuid_map: uuid_map})

    # lets ensure the default category route also works
    message = Messages.create_temp_message(Fixtures.get_org_id(), "123")
    result = Router.execute(router, context, [message])
    assert result == {:ok, nil, []}
  end

  test "router with switch and two cases, category" do
    flow = %Flow{uuid: "Flow UUID 1", id: 1}
    exit_uuid = Ecto.UUID.generate()
    uuid_map = %{}

    json = %{
      "uuid" => "Node UUID",
      "actions" => [],
      "exits" => [
        %{"uuid" => exit_uuid, "destination_uuid" => nil}
      ]
    }

    {node, uuid_map} = Node.process(json, uuid_map, flow)

    json = %{
      "operand" => "@input.text",
      "type" => "switch",
      "default_category_uuid" => "Default Cat UUID",
      "result_name" => "Language",
      "categories" => [
        %{"uuid" => "UUID Cat 1", "exit_uuid" => exit_uuid, "name" => "Category Uno"},
        %{
          "uuid" => "Default Cat UUID",
          "exit_uuid" => exit_uuid,
          "name" => "Default Category"
        }
      ],
      "cases" => [
        %{
          "uuid" => "UUID 1",
          "type" => "has_any_word",
          "arguments" => ["alpha", "beta", "gamma"],
          "category_uuid" => "UUID Cat 1"
        },
        %{
          "uuid" => "UUID 2",
          "type" => "has_number_between",
          "arguments" => ["100", "1000"],
          "category_uuid" => "UUID Cat 1"
        }
      ]
    }

    {router, uuid_map} = Router.process(json, uuid_map, node)

    # create a simple flow context
    context = flow_context_fixture(%{uuid_map: uuid_map})

    message = Messages.create_temp_message(Fixtures.get_org_id(), "alpha")
    result = Router.execute(router, context, [message])

    # we send it to a null node. lets ensure we get the right values
    assert result == {:ok, nil, []}

    # need to recreate the context, since we blew it away when the previous
    # flow finished
    context = flow_context_fixture(%{uuid_map: uuid_map})

    # lets ensure the default category route also works
    message = Messages.create_temp_message(Fixtures.get_org_id(), "123")
    result = Router.execute(router, context, [message])
    assert result == {:ok, nil, []}
  end

  test "router with split by expression with EEx code" do
    flow = %Flow{uuid: "Flow UUID 1", id: 1}
    exit_uuid = Ecto.UUID.generate()
    uuid_map = %{}

    json = %{
      "uuid" => "Node UUID",
      "actions" => [],
      "exits" => [
        %{"uuid" => exit_uuid, "destination_uuid" => nil}
      ]
    }

    {node, uuid_map} = Node.process(json, uuid_map, flow)

    json = %{
      "type" => "switch",
      "default_category_uuid" => "Default Cat UUID",
      "result_name" => "Language",
      "categories" => [
        %{
          "uuid" => "Default Cat UUID",
          "exit_uuid" => exit_uuid,
          "name" => "Default Category"
        }
      ],
      "cases" => []
    }

    # correct EEx expression
    {router, uuid_map} =
      json
      |> Map.merge(%{"operand" => "<%= rem(5, 2) %>"})
      |> Router.process(uuid_map, node)

    context = flow_context_fixture(%{uuid_map: uuid_map})
    {:ok, _, _} = Router.execute(router, context, [])

    # incorrect EEx expression
    {router, uuid_map} =
      json
      |> Map.merge(%{"operand" => "<% end %>"})
      |> Router.process(uuid_map, node)

    context = flow_context_fixture(%{uuid_map: uuid_map})
    {:ok, _, _} = Router.execute(router, context, [])

    # invalid EEx expression
    {router, uuid_map} =
      json
      |> Map.merge(%{"operand" => "<%= IO.inspect('This is for test') %>"})
      |> Router.process(uuid_map, node)

    context = flow_context_fixture(%{uuid_map: uuid_map})
    {:ok, _, _} = Router.execute(router, context, [])
  end

  test "router with split by expression with EEx code for wa_group flow", attrs do
    flow = %Flow{uuid: "Flow UUID 1", id: 1}
    exit_uuid = Ecto.UUID.generate()
    uuid_map = %{}

    json = %{
      "uuid" => "Node UUID",
      "actions" => [],
      "exits" => [
        %{"uuid" => exit_uuid, "destination_uuid" => nil}
      ]
    }

    {node, uuid_map} = Node.process(json, uuid_map, flow)

    json = %{
      "type" => "switch",
      "default_category_uuid" => "Default Cat UUID",
      "result_name" => "Language",
      "categories" => [
        %{
          "uuid" => "Default Cat UUID",
          "exit_uuid" => exit_uuid,
          "name" => "Default Category"
        }
      ],
      "cases" => [
        %{
          "id" => nil,
          "uuid" => "e254c8f0-69e7-4911-9b65-577a54b9de7e",
          "name" => nil,
          "type" => "has_only_phrase",
          "arguments" => ["true"],
          "parsed_arguments" => nil,
          "category_uuid" => "Default Cat UUID",
          "category" => nil
        },
        %{
          "id" => nil,
          "uuid" => "e254c8f0-69e7-4911-9b65-577a54b9de7e",
          "name" => nil,
          "type" => "has_number_eq",
          "arguments" => ["true"],
          "parsed_arguments" => nil,
          "category_uuid" => "Default Cat UUID",
          "category" => nil
        }
      ]
    }

    # correct EEx expression
    {router, uuid_map} =
      json
      |> Map.merge(%{"operand" => "<%= rem(5, 2) %>"})
      |> Router.process(uuid_map, node)

    context =
      Fixtures.wa_flow_context_fixture(%{
        uuid_map: uuid_map,
        organization_id: attrs.organization_id,
        phone: Phone.EnUs.phone()
      })

    assert {:ok, _, _} = Router.execute(router, context, [])

    {router, uuid_map} =
      json
      |> Map.put("cases", [
        %{
          "id" => nil,
          "uuid" => "e254c8f0-69e7-4911-9b65-577a54b9de7e",
          "name" => nil,
          "type" => "has_number_eq",
          "arguments" => ["true"],
          "parsed_arguments" => nil,
          "category_uuid" => "Default Cat UUID",
          "category" => nil
        }
      ])
      |> Map.merge(%{"operand" => "<%= rem(5, 2) %>"})
      |> Router.process(uuid_map, node)

    context =
      flow_context_fixture(%{
        uuid_map: uuid_map,
        organization_id: attrs.organization_id,
        phone: Phone.EnUs.phone()
      })

    assert {:ok, _, _} = Router.execute(router, context, [])
  end

  test "router with split by groups" do
    flow = %Flow{uuid: "Flow UUID 1", id: 1}
    exit_uuid = Ecto.UUID.generate()
    uuid_map = %{}

    json = %{
      "uuid" => "Node UUID",
      "actions" => [],
      "exits" => [
        %{"uuid" => exit_uuid, "destination_uuid" => nil}
      ]
    }

    {node, uuid_map} = Node.process(json, uuid_map, flow)

    json = %{
      "type" => "switch",
      "default_category_uuid" => "Default Cat UUID",
      "result_name" => "Language",
      "categories" => [
        %{
          "uuid" => "Default Cat UUID",
          "exit_uuid" => exit_uuid,
          "name" => "Default Category"
        }
      ],
      "cases" => []
    }

    # correct EEx expression
    {router, uuid_map} =
      json
      |> Map.merge(%{"operand" => "@contact.groups"})
      |> Router.process(uuid_map, node)

    context = flow_context_fixture(%{uuid_map: uuid_map})
    [group | _] = Groups.list_groups(%{filter: %{organization_id: context.organization_id}})

    Groups.create_contact_group(%{
      contact_id: context.contact_id,
      group_id: group.id,
      organization_id: context.organization_id
    })

    {:ok, _, _} = Router.execute(router, context, [])
  end
end
