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

  test "validate/3 surfaces the specific interpreter reason for a bad operand", %{
    organization_id: organization_id
  } do
    router = %Router{
      type: "switch",
      operand: ~s|<%= System.cmd("id", []) %>|,
      node_uuid: Ecto.UUID.generate(),
      categories: [],
      cases: [],
      wait: nil
    }

    assert [{EEx, message, "Critical"}] =
             Router.validate(router, [], %Flow{organization_id: organization_id})

    assert message =~ "has unsupported expression:"
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

  test "router with whatsapp_form_response stores list values as comma-separated strings" do
    flow = %Flow{uuid: "Flow UUID 1", id: 1}
    exit_uuid = Ecto.UUID.generate()
    uuid_map = %{}

    json = %{
      "uuid" => "Node UUID",
      "actions" => [],
      "exits" => [%{"uuid" => exit_uuid, "destination_uuid" => nil}]
    }

    {node, uuid_map} = Node.process(json, uuid_map, flow)

    json = %{
      "operand" => "@input.text",
      "type" => "switch",
      "default_category_uuid" => "Default Cat UUID",
      "result_name" => "form_result",
      "categories" => [
        %{
          "uuid" => "Default Cat UUID",
          "exit_uuid" => exit_uuid,
          "name" => "Default Category"
        }
      ],
      "cases" => []
    }

    {router, uuid_map} = Router.process(json, uuid_map, node)

    context = flow_context_fixture(%{uuid_map: uuid_map})

    raw_response = %{
      "flow_token" => "unused",
      "multiple_choice" => ["Option_1", "Option_2"],
      "single_choice" => "Option_1"
    }

    message =
      Messages.create_temp_message(
        Fixtures.get_org_id(),
        "form submitted",
        type: :whatsapp_form_response,
        whatsapp_form_response: %{raw_response: raw_response}
      )

    {:ok, _, _} = Router.execute(router, context, [message])

    updated_context = Repo.get!(FlowContext, context.id)

    # the multi-select list should be joined into a comma-separated string
    assert updated_context.results["form_result"]["multiple_choice"] == "Option_1, Option_2"
    # non-list values should be left untouched
    assert updated_context.results["form_result"]["single_choice"] == "Option_1"
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

defmodule Glific.Flows.RouterStructuredOperandTest do
  @moduledoc "Router operands that render a structured value."

  # async: false — the test enables :safe_expressions for the fixtures' org, and
  # the flag is cached in ETS. Running serially keeps it from leaking into the
  # async tests that assert the legacy EEx behaviour for the same org.
  use Glific.DataCase, async: false

  alias FunWithFlags.Flag
  alias FunWithFlags.Store.Cache

  alias Glific.Fixtures

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

  setup do
    # Structured rendering lives in the safe interpreter, so an operand only
    # reaches it when :safe_expressions is on for the org.
    organization_id = Fixtures.get_org_id()
    FunWithFlags.enable(:safe_expressions, for_actor: %{organization_id: organization_id})

    # The toggle row rolls back with the SQL sandbox, but the ETS cache does not
    # (900s TTL). on_exit runs after the sandbox connection is gone, so a
    # FunWithFlags.disable/2 would fail on its DB write — cache a gate-less flag
    # (which reads as disabled) instead. Scoped to this one flag deliberately:
    # Cache.flush/0 would evict every other test's cached flags too.
    on_exit(fn ->
      Cache.put(Flag.new(:safe_expressions, []))
    end)

    %{organization_id: organization_id}
  end

  defp flow_context_fixture(attrs) do
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

  # A switch router whose only case is `has_phrase "Pune"`, so the category it
  # lands in tells us what the operand actually rendered to.
  defp pune_router(operand) do
    exit_uuid = Ecto.UUID.generate()

    {node, uuid_map} =
      Node.process(
        %{
          "uuid" => "Node UUID",
          "actions" => [],
          "exits" => [%{"uuid" => exit_uuid, "destination_uuid" => nil}]
        },
        %{},
        %Flow{uuid: "Flow UUID 1", id: 1}
      )

    %{
      "type" => "switch",
      "operand" => operand,
      "result_name" => "structured",
      "default_category_uuid" => "Other Cat UUID",
      "categories" => [
        %{"uuid" => "Pune Cat UUID", "exit_uuid" => exit_uuid, "name" => "Has Pune"},
        %{"uuid" => "Other Cat UUID", "exit_uuid" => exit_uuid, "name" => "Other"}
      ],
      "cases" => [
        %{
          "uuid" => Ecto.UUID.generate(),
          "type" => "has_phrase",
          "arguments" => ["Pune"],
          "category_uuid" => "Pune Cat UUID"
        }
      ]
    }
    |> Router.process(uuid_map, node)
  end

  # The node's only exit has no destination, so executing it completes the flow
  # and hands back a nil context — read the results off the persisted row.
  defp route(operand) do
    {router, uuid_map} = pune_router(operand)
    context = flow_context_fixture(%{uuid_map: uuid_map})

    {:ok, _, _} = Router.execute(router, context, [])

    Repo.get!(FlowContext, context.id).results["structured"]
  end

  # A map operand used to render as the literal string "Invalid Code", which
  # matched no case and silently routed the contact to Other.
  test "a map operand renders as JSON and matches its contents" do
    result = route(~s|<%= %{"city" => "Pune", "grade" => 9} %>|)

    assert result["input"] == ~s({"city":"Pune","grade":9})
    assert result["category"] == "Has Pune"
  end

  test "a list operand renders comma separated and matches its contents" do
    result = route(~s|<%= ["Nagpur", "Pune"] %>|)

    assert result["input"] == "Nagpur, Pune"
    assert result["category"] == "Has Pune"
  end

  test "a map operand that does not match still routes to the default category" do
    result = route(~s|<%= %{"city" => "Nagpur"} %>|)

    assert result["input"] == ~s({"city":"Nagpur"})
    assert result["category"] == "Other"
  end

  test "a scalar pulled out of a map keeps working" do
    result = route(~s|<%= Map.get(%{"city" => "Pune"}, "city") %>|)

    assert result["input"] == "Pune"
    assert result["category"] == "Has Pune"
  end
end
