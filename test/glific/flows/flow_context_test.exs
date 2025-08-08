defmodule Glific.Flows.FlowContextTest do
  use Glific.DataCase, async: false
  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Fixtures,
    Groups.WAGroups,
    Messages,
    Repo,
    Seeds.SeedsDev,
    WAGroup.WAMessage
  }

  alias Glific.Flows.{
    Action,
    Category,
    Flow,
    FlowContext,
    FlowResult,
    Node
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

  test "create_flow_context/1 will create a new flow context", attrs do
    # create a simple flow context
    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: Fixtures.contact_fixture().id,
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        uuid_map: %{},
        organization_id: attrs.organization_id
      })

    assert context.id != nil
  end

  test "reset_context/1 will reset the context", attrs do
    node = %Node{uuid: Ecto.UUID.generate()}

    json = %{
      "uuid" => Ecto.UUID.generate(),
      "type" => "enter_flow",
      "flow" => %{"uuid" => Ecto.UUID.generate()}
    }

    {_, uuid_map} = Action.process(json, %{}, node)

    {:ok, context_2} =
      FlowContext.create_flow_context(%{
        contact_id: Fixtures.contact_fixture().id,
        flow_id: 1,
        flow_uuid: json["flow"]["uuid"],
        uuid_map: uuid_map,
        organization_id: attrs.organization_id
      })

    FlowContext.reset_context(context_2)
  end

  test "update_flow_context/2 will update the UUID for the current context node" do
    flow_context = flow_context_fixture()
    uuid = Ecto.UUID.generate()
    {:ok, flow_context_2} = FlowContext.update_flow_context(flow_context, %{node_uuid: uuid})
    assert flow_context_2.node_uuid == uuid
  end

  test "update_results/2 will update the results object for the context" do
    flow_context = flow_context_fixture()
    json = %{"uuid" => "UUID 1", "exit_uuid" => "UUID 2", "name" => "Default Category"}
    {category, _uuid_map} = Category.process(json, %{})

    FlowContext.update_results(flow_context, %{
      "test_key" => %{"input" => "test_input", "category" => category.name}
    })

    flow_context = Repo.get!(FlowContext, flow_context.id)

    assert flow_context.results["test_key"] == %{
             "input" => "test_input",
             "category" => category.name
           }

    flow_context =
      flow_context_fixture()
      |> FlowContext.update_results(%{"one more key" => %{"value" => 42}})
      |> FlowContext.update_results(%{"integer value" => 23})

    flow_context = Repo.get!(FlowContext, flow_context.id)
    assert flow_context.results["one more key"] == %{"value" => 42}
    assert flow_context.results["integer value"] == 23

    {:ok, flow_result} = Repo.fetch_by(FlowResult, %{flow_context_id: flow_context.id})
    assert flow_result.results["one more key"] == %{"value" => 42}
    assert flow_result.results["integer value"] == 23
  end

  test "set_node/2 will set the node object for the context" do
    flow_context = flow_context_fixture()
    node = %Node{uuid: Ecto.UUID.generate()}
    flow_context = FlowContext.set_node(flow_context, node)
    assert flow_context.node == node
  end

  test "init_context/3 will initaite a flow context",
       %{organization_id: organization_id} = attrs do
    [flow | _tail] = Glific.Flows.list_flows(%{filter: attrs})
    [keyword | _] = flow.keywords
    flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: keyword})
    contact = Fixtures.contact_fixture()
    {:ok, flow_context, _} = FlowContext.init_context(flow, contact, "published")
    assert flow_context.id != nil
  end

  test "execute an context for a empty node with return the error" do
    flow_context = flow_context_fixture()
    assert {:error, _message} = FlowContext.execute(flow_context, [])
  end

  test "execute an context should return ok tuple", %{organization_id: organization_id} = attrs do
    [flow | _tail] = Glific.Flows.list_flows(%{filter: attrs})
    [keyword | _] = flow.keywords
    flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: keyword})
    contact = Fixtures.contact_fixture()
    {:ok, flow_context, _} = FlowContext.init_context(flow, contact, "published")
    message = Messages.create_temp_message(Fixtures.get_org_id(), "Test")
    assert {:ok, _, _} = FlowContext.execute(flow_context, [message])
  end

  test "active_context/1 will return the current context for contact" do
    flow_context = flow_context_fixture()
    flow_context_2 = FlowContext.active_context(flow_context.contact_id)
    assert flow_context.id == flow_context_2.id
  end

  test "load_context/2 will load all the nodes and actions in memory for the context",
       %{organization_id: organization_id} = _attrs do
    flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "help"})
    [node | _tail] = flow.nodes
    flow_context = flow_context_fixture(%{node_uuid: node.uuid})
    flow_context = FlowContext.load_context(flow_context, flow)
    assert flow_context.uuid_map == flow.uuid_map
  end

  test "load_context/2 will load all the nodes and actions in memory for the context for wa_group",
       %{organization_id: organization_id} = _attrs do
    flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "help"})
    [node | _tail] = flow.nodes

    flow_context =
      Fixtures.wa_flow_context_fixture(%{node_uuid: node.uuid, organization_id: organization_id})

    flow_context = FlowContext.load_context(flow_context, flow)
    assert flow_context.uuid_map == flow.uuid_map
  end

  test "step_forward/2 will set the context to next node ",
       %{organization_id: organization_id} = _attrs do
    flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "help"})
    [node | _tail] = flow.nodes
    flow_context = flow_context_fixture(%{node_uuid: node.uuid})
    flow_context = FlowContext.load_context(flow_context, flow)
    message = Messages.create_temp_message(Fixtures.get_org_id(), "help")
    assert {:ok, _map} = FlowContext.step_forward(flow_context, message)
  end

  test "step_forward/2 will set the context to next node, wa_group ",
       %{organization_id: organization_id} = _attrs do
    flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "help"})
    [node | _tail] = flow.nodes

    flow_context =
      Fixtures.wa_flow_context_fixture(%{node_uuid: node.uuid, organization_id: organization_id})

    flow_context = FlowContext.load_context(flow_context, flow)
    message = Messages.create_temp_message(Fixtures.get_org_id(), "help")
    assert {:ok, _map} = FlowContext.step_forward(flow_context, message)
  end

  test "delete_completed_flow_contexts will delete all contexts completed before three days" do
    flow_context =
      flow_context_fixture(%{
        completed_at: DateTime.utc_now() |> DateTime.add(-(3 * 24 * 60 * 60 + 1), :second)
      })

    FlowContext.delete_completed_flow_contexts()

    assert {:error, _} = Repo.fetch(FlowContext, flow_context.id)
  end

  test "delete_old_flow_contexts will delete all contexts older than 30 days" do
    flow_context = flow_context_fixture()

    last_month_date = DateTime.utc_now() |> DateTime.add(-31 * 24 * 60 * 60, :second)

    FlowContext
    |> where([f], f.id == ^flow_context.id)
    |> Repo.update_all(set: [inserted_at: last_month_date])

    FlowContext.delete_old_flow_contexts()

    assert {:error, _} = Repo.fetch(FlowContext, flow_context.id)
  end

  test "reset_all_contexts/1 will resets all the context for the contact",
       %{organization_id: organization_id} = _attrs do
    flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "help"})
    [node | _tail] = flow.nodes
    flow_context = flow_context_fixture(%{node_uuid: node.uuid})

    # check for the contact
    assert not is_nil(FlowContext.active_context(flow_context.contact_id))
    FlowContext.reset_all_contexts(flow_context, "Message One")
    assert is_nil(FlowContext.active_context(flow_context.contact_id))

    # check for the context
    flow_context = Repo.get!(FlowContext, flow_context.id)
    assert is_nil(flow_context.node)
    assert not is_nil(flow_context.completed_at)
  end

  test "wakeup_one/1 will process all the context for the contact",
       %{organization_id: organization_id} = _attrs do
    flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "help"})
    [node | _tail] = flow.nodes

    message = Messages.create_temp_message(organization_id, "1")
    wakeup_at = Timex.shift(Timex.now(), minutes: -3)

    flow_context =
      flow_context_fixture(%{
        node_uuid: node.uuid,
        wakeup_at: wakeup_at,
        is_background_flow: true,
        flow_uuid: flow.uuid,
        flow_id: flow.id
      })

    assert {:ok, _context, []} = FlowContext.wakeup_one(flow_context, message)

    flow_context = Repo.get!(FlowContext, flow_context.id)
    assert flow_context.wakeup_at == nil
    assert flow_context.is_background_flow == false
  end

  test "wakeup_one/1 will process all the context for the contact, wa_group",
       %{organization_id: organization_id} = _attrs do
    flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "help"})
    [node | _tail] = flow.nodes

    message = Messages.create_temp_message(organization_id, "1")
    wakeup_at = Timex.shift(Timex.now(), minutes: -3)

    flow_context =
      Fixtures.wa_flow_context_fixture(%{
        node_uuid: node.uuid,
        wakeup_at: wakeup_at,
        is_background_flow: true,
        flow_uuid: flow.uuid,
        flow_id: flow.id,
        organization_id: organization_id
      })

    assert {:ok, _context, []} = FlowContext.wakeup_one(flow_context, message)

    flow_context = Repo.get!(FlowContext, flow_context.id)
    assert flow_context.wakeup_at == nil
    assert flow_context.is_background_flow == false
  end

  test "resume_contact_flow/3 will process all the context for the contact",
       %{organization_id: organization_id} = _attrs do
    flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "help"})
    [node | _tail] = flow.nodes

    message = Messages.create_temp_message(organization_id, "1")
    wakeup_at = Timex.shift(Timex.now(), minutes: +3)

    flow_context =
      flow_context_fixture(%{
        node_uuid: node.uuid,
        is_await_result: true,
        wakeup_at: wakeup_at,
        is_background_flow: true,
        flow_uuid: flow.uuid,
        flow_id: flow.id
      })

    assert {:ok, _context, []} =
             FlowContext.resume_contact_flow(
               %{id: flow_context.contact_id},
               flow.id,
               %{unit_test: %{first: 1, second: "two"}},
               message
             )

    flow_context = Repo.get!(FlowContext, flow_context.id)
    assert flow_context.wakeup_at == nil
    assert flow_context.is_background_flow == false
    assert flow_context.is_await_result == false
  end

  describe "init_wa_group_context/3" do
    setup do
      SeedsDev.seed_test_flows()
      default_provider = SeedsDev.seed_providers()
      SeedsDev.seed_organizations(default_provider)
      SeedsDev.seed_contacts()
      SeedsDev.seed_wa_managed_phones()
      SeedsDev.seed_wa_groups()
      :ok
    end

    test "init_wa_group_context/3 will initiate a flow context for wa_groups",
         %{organization_id: organization_id} = attrs do
      [flow | _tail] =
        Glific.Flows.list_flows(%{filter: attrs |> Map.put(:name, "Whatsapp Group")})

      [keyword | _] = flow.keywords
      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: keyword})

      [wa_group | _tail] = WAGroups.list_wa_groups(%{})

      {:ok, _flow_context, _} = FlowContext.init_wa_group_context(flow, wa_group.id, "published")

      [wa_message | _wa_messages] =
        WAMessage
        |> where([wam], wam.organization_id == ^organization_id)
        |> Repo.all()

      assert wa_message.body == "Welcome to WA group feature"
    end

    test "both wa_group_id and contact_id cannot be nil in flow_context", attrs do
      [flow | _tail] =
        Glific.Flows.list_flows(%{filter: attrs |> Map.put(:name, "Whatsapp Group")})

      assert {:error,
              %{errors: [contact_id: {"both contact_id and wa_group_id can't be nil", []}]}} =
               FlowContext.create_flow_context(%{
                 flow_uuid: flow.uuid,
                 status: "success",
                 flow_id: flow.id,
                 organization_id: flow.organization_id
               })
    end

    test "both wa_group_id and contact_id can't be non-nil in flow_context", attrs do
      [flow | _tail] =
        Glific.Flows.list_flows(%{filter: attrs |> Map.put(:name, "Whatsapp Group")})

      [wa_group | _tail] = WAGroups.list_wa_groups(%{})
      [contact | _] = Contacts.list_contacts(%{})

      assert {:error,
              %{errors: [wa_group_id: {"both contact_id and wa_group_id can't be non-nil", []}]}} =
               FlowContext.create_flow_context(%{
                 flow_uuid: flow.uuid,
                 status: "success",
                 flow_id: flow.id,
                 organization_id: flow.organization_id,
                 wa_group_id: wa_group.id,
                 contact_id: contact.id
               })
    end

    test "Either wa_group_id or contact_id should be non-nil in flow_context", attrs do
      [flow | _tail] =
        Glific.Flows.list_flows(%{filter: attrs |> Map.put(:name, "Whatsapp Group")})

      [wa_group | _tail] = WAGroups.list_wa_groups(%{})
      [_contact | _] = Contacts.list_contacts(%{})

      assert {:ok, _} =
               FlowContext.create_flow_context(%{
                 flow_uuid: flow.uuid,
                 status: "success",
                 flow_id: flow.id,
                 organization_id: flow.organization_id,
                 wa_group_id: wa_group.id
               })
    end

    test "update operation ignores the valdiation", attrs do
      [flow | _tail] =
        Glific.Flows.list_flows(%{filter: attrs |> Map.put(:name, "Whatsapp Group")})

      [wa_group | _tail] = WAGroups.list_wa_groups(%{})
      [_contact | _] = Contacts.list_contacts(%{})

      {:ok, flow_context} =
        FlowContext.create_flow_context(%{
          flow_uuid: flow.uuid,
          status: "success",
          flow_id: flow.id,
          organization_id: flow.organization_id,
          wa_group_id: wa_group.id
        })

      assert {:ok, _flow_context_2} =
               FlowContext.update_flow_context(flow_context, %{status: "failed"})
    end
  end

  test "match_outbound calculation where body is not empty", attrs do
    {context, contact, node_uuid} = get_context_details(attrs)

    base_time =
      DateTime.utc_now()
      |> DateTime.truncate(:second)

    message = "hello"

    recent_outbound =
      Enum.map(0..3, fn index ->
        date =
          DateTime.add(base_time, -index * 5, :second)
          |> DateTime.to_iso8601()

        %{
          "contact" => %{"name" => contact.name, "uuid" => contact.id},
          "date" => date,
          "message" => message,
          "message_id" => index,
          "node_uuid" => node_uuid
        }
      end)

    {:ok, context} =
      FlowContext.update_flow_context(context, %{
        recent_outbound:
          recent_outbound ++
            [
              %{
                "contact" => %{"name" => contact.name, "uuid" => contact.id},
                "date" => DateTime.add(base_time, 300, :second),
                "message" => message,
                "message_id" => 10,
                "node_uuid" => "8b4d2e09-9d72-4436-a01a-8e3def9cf4e1"
              }
            ]
      })

    assert FlowContext.match_outbound(context, message) == 4
  end

  test "match_outbound calculation where body is empty, but recent_outbound doesnt have type and media attrs",
       attrs do
    {context, contact, node_uuid} = get_context_details(attrs)

    base_time =
      DateTime.utc_now()
      |> DateTime.truncate(:second)

    message = "hello"

    recent_outbound =
      Enum.map(0..3, fn index ->
        date =
          DateTime.add(base_time, -index * 5, :second)
          |> DateTime.to_iso8601()

        %{
          "contact" => %{"name" => contact.name, "uuid" => contact.id},
          "date" => date,
          "message" => message,
          "message_id" => index,
          "node_uuid" => node_uuid
        }
      end)

    {:ok, context} =
      FlowContext.update_flow_context(context, %{
        recent_outbound:
          recent_outbound ++
            [
              %{
                "contact" => %{"name" => contact.name, "uuid" => contact.id},
                "date" => DateTime.add(base_time, 300, :second),
                "message" => "",
                "message_id" => 10,
                "node_uuid" => node_uuid
              }
            ]
      })

    # This is an edge case where message_type and message_media won't be in recent_outbound
    # this is the case for older flow_contexts. But body being empty string going into infinity loop
    # itself is an edge case, so this issue won't be in future flow_contexts.
    assert FlowContext.match_outbound(context, "") == 5
  end

  test "match_outbound calculation where body is empty, and recent_outbound have type and media attrs",
       attrs do
    {context, contact, node_uuid} = get_context_details(attrs)

    base_time =
      DateTime.utc_now()
      |> DateTime.truncate(:second)

    message = "hello"

    recent_outbound =
      Enum.map(0..3, fn index ->
        date =
          DateTime.add(base_time, -index * 5, :second)
          |> DateTime.to_iso8601()

        %{
          "contact" => %{"name" => contact.name, "uuid" => contact.id},
          "date" => date,
          "message" => message,
          "message_id" => index,
          "node_uuid" => node_uuid
        }
      end)

    {:ok, context} =
      FlowContext.update_flow_context(context, %{
        recent_outbound:
          recent_outbound ++
            [
              %{
                "contact" => %{"name" => contact.name, "uuid" => contact.id},
                "date" => DateTime.add(base_time, 300, :second),
                "message" => "",
                "message_id" => 10,
                "node_uuid" => "8b4d2e09-9d72-4436-a01a-8e3def9cf4e5",
                "message_type" => "image",
                "message_media" => "https://acme.org/img.jpg"
              }
            ]
      })

    assert FlowContext.match_outbound(context, "", "https://acme.org/img.jpg") == 1
  end

  test "match_outbound calculation where body is empty, but there are multiple distinct media for a node",
       attrs do
    {context, contact, node_uuid} = get_context_details(attrs)

    base_time =
      DateTime.utc_now()
      |> DateTime.truncate(:second)

    message = "hello"

    recent_outbound =
      Enum.map(0..2, fn index ->
        date =
          DateTime.add(base_time, -index * 5, :second)
          |> DateTime.to_iso8601()

        %{
          "contact" => %{"name" => contact.name, "uuid" => contact.id},
          "date" => date,
          "message" => message,
          "message_id" => index,
          "node_uuid" => "8b4d2e09-9d72-4436-a01a-8e3def9cf4312"
        }
      end)

    {:ok, context} =
      FlowContext.update_flow_context(context, %{
        recent_outbound:
          recent_outbound ++
            [
              %{
                "contact" => %{"name" => contact.name, "uuid" => contact.id},
                "date" => DateTime.add(base_time, 300, :second),
                "message" => "",
                "message_id" => 10,
                "node_uuid" => node_uuid,
                "message_type" => "image",
                "message_media" => "https://acme.org/img.jpg"
              },
              %{
                "contact" => %{"name" => contact.name, "uuid" => contact.id},
                "date" => DateTime.add(base_time, 1000, :second),
                "message" => "",
                "message_id" => 10,
                "node_uuid" => node_uuid,
                "message_type" => "image",
                "message_media" => "https://acme.org/img2.jpg"
              }
            ]
      })

    assert FlowContext.match_outbound(context, "", "https://acme.org/img.jpg") == 1
  end

  test "match_outbound calculation where body is empty, but there are multiple same media for a node",
       attrs do
    {context, contact, node_uuid} = get_context_details(attrs)

    base_time =
      DateTime.utc_now()
      |> DateTime.truncate(:second)

    message = "hello"

    recent_outbound =
      Enum.map(0..2, fn index ->
        date =
          DateTime.add(base_time, -index * 5, :second)
          |> DateTime.to_iso8601()

        %{
          "contact" => %{"name" => contact.name, "uuid" => contact.id},
          "date" => date,
          "message" => message,
          "message_id" => index,
          "node_uuid" => "8b4d2e09-9d72-4436-a01a-8e3def9cf4312"
        }
      end)

    {:ok, context} =
      FlowContext.update_flow_context(context, %{
        recent_outbound:
          recent_outbound ++
            [
              %{
                "contact" => %{"name" => contact.name, "uuid" => contact.id},
                "date" => DateTime.add(base_time, 300, :second),
                "message" => "",
                "message_id" => 10,
                "node_uuid" => node_uuid,
                "message_type" => "image",
                "message_media" => "https://acme.org/img.jpg"
              },
              %{
                "contact" => %{"name" => contact.name, "uuid" => contact.id},
                "date" => DateTime.add(base_time, 1000, :second),
                "message" => "",
                "message_id" => 10,
                "node_uuid" => node_uuid,
                "message_type" => "image",
                "message_media" => "https://acme.org/img.jpg"
              },
              %{
                "contact" => %{"name" => contact.name, "uuid" => contact.id},
                "date" => DateTime.add(base_time, -2, :day),
                "message" => "",
                "message_id" => 10,
                "node_uuid" => node_uuid,
                "message_type" => "image",
                "message_media" => "https://acme.org/img.jpg"
              }
            ]
      })

    assert FlowContext.match_outbound(context, "", "https://acme.org/img.jpg") == 2
  end

  defp get_context_details(attrs) do
    [flow | _tail] = Glific.Flows.list_flows(%{filter: attrs})
    node_uuid = "8b4d2e09-9d72-4436-a01a-8e3def9cf4e5"

    [contact | _] = Contacts.list_contacts(%{})

    context_attrs = %{
      flow_id: flow.id,
      flow_uuid: flow.uuid,
      contact_id: contact.id,
      organization_id: attrs.organization_id,
      node_uuid: node_uuid
    }

    {:ok, context} = FlowContext.create_flow_context(context_attrs)
    {context, contact, node_uuid}
  end
end
