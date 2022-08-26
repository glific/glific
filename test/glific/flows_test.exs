defmodule Glific.FLowsTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Flows,
    Flows.Broadcast,
    Flows.Flow,
    Flows.FlowBroadcast,
    Flows.FlowContext,
    Flows.FlowRevision,
    Groups,
    Messages,
    Messages.Message,
    Processor.ConsumerWorker,
    Repo,
    Seeds.SeedsDev
  }

  describe "flows" do
    @valid_attrs %{
      name: "Test Flow",
      keywords: ["test_keyword"],
      flow_type: :message,
      version_number: "13.1.0"
    }

    @valid_more_attrs %{
      name: "Test Flow More",
      flow_type: :message,
      keywords: ["test_keyword_2"],
      version_number: "13.1.0"
    }

    @invalid_attrs %{
      name: "Test Flow",
      flow_type: :message_2,
      version_number: "13.1.0",
      organization_id: 1
    }

    @update_attrs %{
      name: "Update flow",
      keywords: ["update_keyword"]
    }

    def flow_fixture(attrs \\ %{}),
      do: Fixtures.flow_fixture(attrs)

    test "list_flows/0 returns all flows", attrs do
      flow = flow_fixture()
      flows = Flows.list_flows(%{filter: attrs})
      assert Enum.filter(flows, fn fl -> fl.name == flow.name end) == [flow]
    end

    test "list_flows/1 returns flows filtered by keyword", attrs do
      f0 = flow_fixture(@valid_attrs)
      _f1 = flow_fixture(@valid_more_attrs)

      flows = Flows.list_flows(%{filter: Map.merge(attrs, %{keyword: "testkeyword"})})
      assert flows == [f0]

      flows = Flows.list_flows(%{filter: Map.merge(attrs, %{keyword: "wrongkeyword"})})
      assert flows == []

      flows = Flows.list_flows(%{filter: Map.merge(attrs, %{wrong_filter: "test"})})
      assert length(flows) >= 2
    end

    test "list_flows/1 returns flows filtered by is_pinned", attrs do
      [predefine_flow | _tail] = Flows.list_flows(%{filter: attrs})

      assert {:ok, %Flow{} = _flow} =
               @valid_attrs
               |> Map.merge(%{
                 organization_id: predefine_flow.organization_id,
                 is_pinned: true
               })
               |> Flows.create_flow()

      flows = Flows.list_flows(%{filter: %{is_pinned: true}})
      assert length(flows) == 2
    end

    test "list_flows/1 returns flows filtered by name keyword", attrs do
      f0 = flow_fixture(@valid_attrs)
      f1 = flow_fixture(@valid_more_attrs |> Map.merge(%{name: "testkeyword"}))

      flows = Flows.list_flows(%{filter: Map.merge(attrs, %{name_or_keyword: "testkeyword"})})
      assert flows == [f0, f1]

      flows = Flows.list_flows(%{filter: Map.merge(attrs, %{name_or_keyword: "wrongkeyword"})})
      assert flows == []

      flows = Flows.list_flows(%{filter: Map.merge(attrs, %{wrong_filter: "test"})})
      assert length(flows) >= 2
    end

    test "count_flows/0 returns count of all flows",
         %{organization_id: organization_id} = attrs do
      flow_count =
        Flow
        |> Ecto.Query.where([q], q.organization_id == ^organization_id)
        |> Repo.aggregate(:count)

      _ = flow_fixture()
      assert Flows.count_flows(%{filter: attrs}) == flow_count + 1

      _ = flow_fixture(@valid_more_attrs)
      assert Flows.count_flows(%{filter: attrs}) == flow_count + 2

      assert Flows.count_flows(%{filter: Map.merge(attrs, %{name: "Help Workflow"})}) == 1
    end

    test "get_flow!/1 returns the flow with given id" do
      flow = flow_fixture()
      assert Flows.get_flow!(flow.id) == flow
    end

    test "fetch_flow/1 returns the flow with given id or returns {:ok, flow} or {:error, any}" do
      flow = flow_fixture()
      {:ok, fetched_flow} = Flows.fetch_flow(flow.id)
      assert fetched_flow.name == flow.name
      assert fetched_flow.status == flow.status
      assert fetched_flow.keywords == flow.keywords
    end

    test "create_flow/1 with valid data creates a flow", attrs do
      [predefine_flow | _tail] = Flows.list_flows(%{filter: attrs})

      assert {:ok, %Flow{} = flow} =
               @valid_attrs
               |> Map.merge(%{organization_id: predefine_flow.organization_id})
               |> Flows.create_flow()

      assert flow.name == @valid_attrs.name
      assert flow.flow_type == @valid_attrs.flow_type
      assert flow.keywords == Enum.map(@valid_attrs.keywords, &Glific.string_clean(&1))
    end

    test "create_flow/1 with valid data creates a background flow", attrs do
      [predefine_flow | _tail] = Flows.list_flows(%{filter: attrs})

      assert {:ok, %Flow{} = flow} =
               @valid_attrs
               |> Map.merge(%{
                 organization_id: predefine_flow.organization_id,
                 is_background: true
               })
               |> Flows.create_flow()

      assert flow.name == @valid_attrs.name
      assert flow.is_background == true
      assert flow.flow_type == @valid_attrs.flow_type
      assert flow.keywords == Enum.map(@valid_attrs.keywords, &Glific.string_clean(&1))
    end

    test "create_flow/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Flows.create_flow(@invalid_attrs)
    end

    test "create_flow/1 with existing keyword returns error changeset", attrs do
      attrs = Map.merge(@valid_attrs, attrs)
      Flows.create_flow(attrs)

      invalid_attrs =
        attrs
        |> Map.merge(%{keywords: ["test_keyword", "test_keyword_2"]})

      assert {:error, %Ecto.Changeset{}} = Flows.create_flow(invalid_attrs)
    end

    test "create_flow/1 with keywords will covert all keywords to downcase", attrs do
      attrs = Map.merge(@valid_attrs, attrs)

      assert {:ok, %Flow{} = flow} =
               attrs
               |> Map.merge(%{keywords: ["Test_Keyword", "TEST_KEYWORD_2"]})
               |> Flows.create_flow()

      assert flow.keywords == ["testkeyword", "testkeyword2"]
    end

    test "create_flow/1 will have a default revision" do
      flow = flow_fixture(@valid_attrs)
      flow = Repo.preload(flow, [:revisions])
      assert flow.name == @valid_attrs.name
      assert flow.flow_type == @valid_attrs.flow_type
      assert is_list(flow.revisions)
      assert length(flow.revisions) > 0
    end

    test "update_flow/2 with valid data updates the flow" do
      flow = flow_fixture()
      assert {:ok, %Flow{} = flow} = Flows.update_flow(flow, @update_attrs)
      assert flow.name == @update_attrs.name
    end

    test "update_flow/2 with invalid data returns error changeset" do
      flow = flow_fixture()
      assert {:error, %Ecto.Changeset{}} = Flows.update_flow(flow, @invalid_attrs)
      assert flow == Flows.get_flow!(flow.id)
    end

    test "update_flow/2 with keywords" do
      flow = flow_fixture()

      valid_attrs =
        @valid_attrs
        |> Map.merge(%{keywords: ["test_keyword", "test_keyword_1"]})

      assert {:ok, %Flow{}} = Flows.update_flow(flow, valid_attrs)

      # update flow with existing keyword should return error
      flow = flow_fixture(@valid_more_attrs)

      invalid_attrs =
        @valid_attrs
        |> Map.merge(%{keywords: ["test_keyword_2", "test_keyword_1"]})

      assert {:error, %Ecto.Changeset{}} = Flows.update_flow(flow, invalid_attrs)
    end

    test "delete_flow/1 deletes the flow" do
      flow = flow_fixture()
      assert {:ok, %Flow{}} = Flows.delete_flow(flow)
      assert_raise Ecto.NoResultsError, fn -> Flows.get_flow!(flow.id) end
    end

    test "change_flow/1 returns a flow changeset" do
      flow = flow_fixture()
      assert %Ecto.Changeset{} = Flows.change_flow(flow)
    end

    test "get_flow_revision_list/1 returns a formatted list of flow revisions" do
      flow =
        flow_fixture()
        |> Repo.preload([:revisions])

      revisions = Flows.get_flow_revision_list(flow.uuid).results
      assert length(flow.revisions) == length(revisions)
    end

    test "get_flow_revision/2 returns a specific revision" do
      flow =
        flow_fixture()
        |> Repo.preload([:revisions])

      [revision] = flow.revisions
      assert Flows.get_flow_revision(flow.uuid, revision.id).definition == revision.definition
    end

    test "create_flow_revision/1 create a specific revision for the flow" do
      flow =
        flow_fixture()
        |> Repo.preload([:revisions])

      [revision] = flow.revisions

      Flows.create_flow_revision(revision.definition)
      current_revisions = Flows.get_flow_revision_list(flow.uuid).results
      assert length(current_revisions) == length(flow.revisions) + 1
    end

    test "check_required_fields/1 check the required field in the json file", attrs do
      [flow | _tail] = Flows.list_flows(%{filter: attrs})
      flow = Repo.preload(flow, [:revisions])
      [revision | _tail] = flow.revisions
      assert Flows.check_required_fields(revision.definition, [:name]) == true
      definition = Map.delete(revision.definition, "name")
      assert_raise ArgumentError, fn -> Flows.check_required_fields(definition, [:name]) end
    end

    test "get_cached_flow/2 save the flow to cache returns a touple and flow",
         %{organization_id: organization_id} = attrs do
      [flow | _tail] = Flows.list_flows(%{filter: attrs})

      {:ok, loaded_flow} =
        Flows.get_cached_flow(organization_id, {:flow_uuid, flow.uuid, "published"})

      assert loaded_flow.nodes != nil

      # Next time Flow will be picked from cache
      Flows.delete_flow(flow)

      {:ok, loaded_flow_2} =
        Flows.get_cached_flow(organization_id, {:flow_uuid, flow.uuid, "published"})

      assert loaded_flow_2 == loaded_flow
    end

    test "update_cached_flow/1 will remove the keys and update the flows" do
      organization_id = Fixtures.get_org_id()
      [flow | _tail] = Flows.list_flows(%{filter: %{organization_id: organization_id}})

      {:ok, loaded_flow} =
        Flows.get_cached_flow(organization_id, {:flow_uuid, flow.uuid, "published"})

      Flows.update_flow(flow, %{:keywords => ["flow_new"]})
      Flows.update_cached_flow(flow, "published")

      {:ok, loaded_flow_new} =
        Flows.get_cached_flow(organization_id, {:flow_uuid, flow.uuid, "published"})

      assert loaded_flow.keywords == flow.keywords
      assert loaded_flow_new.keywords != loaded_flow.keywords
    end

    test "publish_flow/1 updates the latest flow revision status",
         %{organization_id: organization_id} = _attrs do
      SeedsDev.seed_test_flows()

      name = "Language Workflow"
      {:ok, flow} = Repo.fetch_by(Flow, %{name: name, organization_id: organization_id})
      flow = Repo.preload(flow, [:revisions])

      # should set status of recent flow revision as "published"
      assert {:ok, %Flow{}} = Flows.publish_flow(flow)

      {:ok, revision} =
        FlowRevision
        |> Repo.fetch_by(%{flow_id: flow.id, revision_number: 0})

      assert revision.status == "published"

      [revision] = flow.revisions
      # should update the cached flow definition
      {:ok, loaded_flow} =
        Flows.get_cached_flow(organization_id, {:flow_uuid, flow.uuid, "published"})

      assert loaded_flow.definition == revision.definition

      # If a flow revision is already published
      # should reset previously published flow revision and set status of recent one as "published"
      new_definition = revision.definition |> Map.merge(%{"revision" => 2})
      Flows.create_flow_revision(new_definition)

      assert {:ok, %Flow{}} = Flows.publish_flow(flow)

      {:ok, revision} =
        FlowRevision
        |> Repo.fetch_by(%{flow_id: flow.id, revision_number: 0})

      assert revision.status == "published"

      # should update the cached flow definition
      {:ok, loaded_flow} =
        Flows.get_cached_flow(organization_id, {:flow_uuid, flow.uuid, "published"})

      assert loaded_flow.definition == new_definition
    end

    test "start_cotntact_flow/2 will setup the flow for a contact", attrs do
      [flow | _tail] = Flows.list_flows(%{filter: attrs})

      contact = Fixtures.contact_fixture(attrs)

      {:ok, flow} = Flows.start_contact_flow(flow, contact)
      first_action = hd(hd(flow.nodes).actions)

      assert {:ok, _message} =
               Repo.fetch_by(Message, %{uuid: first_action.uuid, contact_id: contact.id})
    end

    test "start_contact_flow/2 if flow is not avialable", attrs do
      contact = Fixtures.contact_fixture(attrs)

      {:error, error} = Flows.start_contact_flow(9999, contact)
      assert error == "Flow not found"
    end

    test "start_contact_flow/2 will setup the template flow for a contact", attrs do
      SeedsDev.seed_session_templates()
      [flow | _tail] = Flows.list_flows(%{filter: %{name: "Template Workflow"}})
      contact = Fixtures.contact_fixture(attrs)
      Flows.start_contact_flow(flow, contact)
      assert {:ok, message} = Repo.fetch_by(Message, %{is_hsm: true, contact_id: contact.id})

      assert message.body ==
               "Download your issue regarding education ticket from the link given below. | [Visit Website,https://www.gupshup.io/developer/issues]"

      contact = Fixtures.contact_fixture(%{language_id: 2})
      Flows.start_contact_flow(flow, contact)
      assert {:ok, message} = Repo.fetch_by(Message, %{is_hsm: true, contact_id: contact.id})

      assert message.body ==
               "नीचे दिए गए लिंक से अपना शिक्षा के संबंध में मुद्दा टिकट डाउनलोड करें। | [Visit Website, https://www.gupshup.io/developer/issues-hin"
    end

    test "start_group_flow/2 will setup the flow for a group of contacts", attrs do
      [flow | _tail] = Flows.list_flows(%{filter: attrs})
      group = Fixtures.group_fixture()
      contact = Fixtures.contact_fixture()
      contact2 = Fixtures.contact_fixture()

      Groups.create_contact_group(%{
        group_id: group.id,
        contact_id: contact.id,
        organization_id: attrs.organization_id
      })

      Groups.create_contact_group(%{
        group_id: group.id,
        contact_id: contact2.id,
        organization_id: attrs.organization_id
      })

      {:ok, flow} = Flows.start_group_flow(flow, group)

      assert {:ok, flow_broadcast} =
               Repo.fetch_by(FlowBroadcast, %{
                 group_id: group.id,
                 flow_id: flow.id
               })

      assert flow_broadcast.completed_at == nil

      # lets sleep for 3 seconds, to ensure that messages have been delivered
      Broadcast.execute_group_broadcasts(attrs.organization_id)
      Process.sleep(3_000)

      first_action = hd(hd(flow.nodes).actions)

      assert {:ok, _message} =
               Repo.fetch_by(Message, %{uuid: first_action.uuid, contact_id: contact.id})

      assert {:ok, _message} =
               Repo.fetch_by(Message, %{uuid: first_action.uuid, contact_id: contact2.id})

      Broadcast.execute_group_broadcasts(attrs.organization_id)

      assert {:ok, flow_broadcast} =
               Repo.fetch_by(FlowBroadcast, %{
                 group_id: group.id,
                 flow_id: flow.id
               })

      assert flow_broadcast.completed_at != nil
    end

    test "copy_flow/2 with valid data makes a copy of flow" do
      flow = flow_fixture()

      attrs = %{
        name: "copied flow",
        keywords: []
      }

      assert {:ok, %Flow{} = copied_flow} = Flows.copy_flow(flow, attrs)
      assert copied_flow.name == attrs.name

      # it should create a copy of flow revision
      {:ok, flow_revision} = Repo.fetch_by(FlowRevision, %{flow_id: flow.id, revision_number: 0})

      assert {:ok, copied_flow_revision} =
               Repo.fetch_by(FlowRevision, %{flow_id: copied_flow.id, revision_number: 0})

      assert copied_flow_revision.definition ==
               flow_revision.definition |> Map.merge(%{"uuid" => copied_flow.uuid})

      # copy a flow without a name gives an error
      assert {:error, %Ecto.Changeset{}} = Flows.copy_flow(flow, %{})
    end

    test "flow keyword map keys are always in lower case", attrs do
      flow = flow_fixture()

      assert {:ok, %Flow{} = flow} =
               Flows.update_flow(flow, %{keywords: ["Hello", "Greetings", "ABCD"]})

      keyword_map = Flows.flow_keywords_map(attrs.organization_id)

      assert nil ==
               Enum.find(keyword_map[flow.status], fn {keyword, _flow_id} ->
                 keyword != Glific.string_clean(keyword)
               end)
    end
  end

  defp expected_error(str) do
    errors = [
      "Your flow has dangling nodes",
      "Could not find Contact:",
      "Could not find Group:",
      "The next message after a long wait for time should be an HSM template",
      "Could not find Sub Flow:",
      "Could not parse"
    ]

    Enum.any?(errors, &String.contains?(str, &1))
  end

  test "test validate and response_other on test workflow" do
    SeedsDev.seed_test_flows()

    {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})

    errors = Flow.validate_flow(flow.organization_id, "draft", %{id: flow.id})
    assert is_list(errors)

    Enum.each(
      errors,
      fn e -> assert expected_error(elem(e, 1)) end
    )
  end

  test "test not setting other option on test workflow",
       %{organization_id: organization_id} = _attrs do
    SeedsDev.seed_test_flows()

    contact = Fixtures.contact_fixture()

    opts = [
      contact_id: contact.id,
      sender_id: contact.id,
      receiver_id: contact.id,
      flow: :inbound
    ]

    message = Messages.create_temp_message(organization_id, "some random message", opts)

    message_count = Repo.aggregate(Message, :count)

    {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})
    {:ok, flow} = Flows.update_flow(flow, %{respond_other: true})

    {:ok, flow} = Flows.get_cached_flow(organization_id, {:flow_uuid, flow.uuid, "published"})

    {:ok, context} = FlowContext.seed_context(flow, contact, "published")

    context |> FlowContext.load_context(flow) |> FlowContext.execute([message])
    new_count = Repo.aggregate(Message, :count)

    assert message_count < new_count
    # since we should have recd 2 messages, hello and hello
    assert message_count + 2 == new_count
  end

  test "test executing the new contact workflow and ensuring parent and child are set",
       %{organization_id: organization_id} = _attrs do
    contact = Fixtures.contact_fixture()

    message_count = Repo.aggregate(Message, :count)
    context_count = Repo.aggregate(FlowContext, :count)

    {:ok, flow} = Repo.fetch_by(Flow, %{name: "New Contact Workflow"})
    {:ok, flow} = Flows.get_cached_flow(organization_id, {:flow_uuid, flow.uuid, "published"})

    {:ok, context} = FlowContext.seed_context(flow, contact, "published")

    {:ok, context, _msgs} =
      context
      |> FlowContext.load_context(flow)
      |> FlowContext.execute([])

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "status" => "submitted",
              "messageId" => Faker.String.base64(36)
            })
        }
    end)

    state = ConsumerWorker.load_state(organization_id)

    message = Fixtures.message_fixture(%{body: "👍", sender_id: contact.id})
    ConsumerWorker.process_message(message, state)

    message = Fixtures.message_fixture(%{body: "2", sender_id: contact.id})
    ConsumerWorker.process_message(message, state)

    db_context = Repo.get!(FlowContext, context.id)
    assert !is_nil(db_context.results)
    assert !is_nil(db_context.results["child"])

    child_context =
      FlowContext
      |> where([fc], is_nil(fc.completed_at))
      |> where([fc], fc.parent_id == ^context.id)
      |> Repo.one!()

    assert !is_nil(child_context.results)
    assert !is_nil(child_context.results["parent"])

    assert message_count < Repo.aggregate(Message, :count)
    assert context_count < Repo.aggregate(FlowContext, :count)
  end

  test "publishing multiple flow revision of a same flow throws and error",
       %{organization_id: organization_id} = _attrs do
    SeedsDev.seed_test_flows()

    name = "Language Workflow"
    {:ok, flow} = Repo.fetch_by(Flow, %{name: name, organization_id: organization_id})
    flow = Repo.preload(flow, [:revisions])

    # should set status of recent flow revision as "published"
    assert {:ok, %Flow{}} = Flows.publish_flow(flow)

    {:ok, revision} =
      FlowRevision
      |> Repo.fetch_by(%{flow_id: flow.id, revision_number: 0})

    assert revision.status == "published"

    [flow_revision | _tail] =
      FlowRevision
      |> where([fr], fr.flow_id == ^flow.id)
      |> Repo.all()

    assert {:error, %Ecto.Changeset{}} =
             flow_revision
             |> FlowRevision.changeset(%{status: "published", revision_number: 0})
             |> Repo.update()
  end
end
