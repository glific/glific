defmodule Glific.FLowsTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Flows,
    Flows.Flow,
    Flows.FlowRevision,
    Groups,
    Messages.Message
  }

  describe "flows" do
    @valid_attrs %{
      name: "Test Flow",
      shortcode: "test_short_code",
      keywords: ["test_keyword"],
      flow_type: :message,
      version_number: "13.1.0"
    }

    @valid_more_attrs %{
      name: "Test Flow More",
      shortcode: "test_short_code_2",
      flow_type: :message,
      keywords: ["test_keyword_2"],
      version_number: "13.1.0"
    }

    @invalid_attrs %{
      name: "Test Flow",
      shortcode: "",
      flow_type: :message_2,
      version_number: "13.1.0"
    }

    @update_attrs %{
      name: "Update flow",
      shortcode: "update shortcode"
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

      flows = Flows.list_flows(%{filter: Map.merge(attrs, %{keyword: "test_keyword"})})
      assert flows == [f0]

      flows = Flows.list_flows(%{filter: Map.merge(attrs, %{keyword: "wrong_keyword"})})
      assert flows == []

      flows = Flows.list_flows(%{filter: Map.merge(attrs, %{wrong_filter: "test"})})
      assert length(flows) >= 2
    end

    test "count_flows/0 returns count of all flows", attrs do
      flow_count = Repo.aggregate(Flow, :count)

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

    test "create_flow/1 with valid data creates a flow", attrs do
      [predefine_flow | _tail] = Flows.list_flows(%{filter: attrs})

      assert {:ok, %Flow{} = flow} =
               @valid_attrs
               |> Map.merge(%{organization_id: predefine_flow.organization_id})
               |> Flows.create_flow()

      assert flow.name == @valid_attrs.name
      assert flow.flow_type == @valid_attrs.flow_type
      assert flow.shortcode == @valid_attrs.shortcode
    end

    test "create_flow/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Flows.create_flow(@invalid_attrs)
    end

    test "create_flow/1 with existing keyword returns error changeset" do
      Flows.create_flow(@valid_attrs)

      invalid_attrs =
        @valid_attrs
        |> Map.merge(%{keywords: ["test_keyword", "test_keyword_2"]})

      assert {:error, %Ecto.Changeset{}} = Flows.create_flow(invalid_attrs)
    end

    test "create_flow/1 will have a default revision" do
      flow = flow_fixture(@valid_attrs)
      flow = Glific.Repo.preload(flow, [:revisions])
      assert flow.name == @valid_attrs.name
      assert flow.flow_type == @valid_attrs.flow_type
      assert [revision] = flow.revisions
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

      assert {:ok, %Flow{} = flow} = Flows.update_flow(flow, valid_attrs)

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
        |> Glific.Repo.preload([:revisions])

      revisions = Flows.get_flow_revision_list(flow.uuid).results
      assert length(flow.revisions) == length(revisions)
    end

    test "get_flow_revision/2 returns a specific revision" do
      flow =
        flow_fixture()
        |> Glific.Repo.preload([:revisions])

      [revision] = flow.revisions
      assert Flows.get_flow_revision(flow.uuid, revision.id).definition == revision.definition
    end

    test "create_flow_revision/1 create a specific revision for the flow" do
      flow =
        flow_fixture()
        |> Glific.Repo.preload([:revisions])

      [revision] = flow.revisions

      Flows.create_flow_revision(revision.definition)
      current_revisions = Flows.get_flow_revision_list(flow.uuid).results
      assert length(current_revisions) == length(flow.revisions) + 1
    end

    test "check_required_fields/1 check the required field in the json file", attrs do
      [flow | _tail] = Flows.list_flows(%{filter: attrs})
      flow = Glific.Repo.preload(flow, [:revisions])
      [revision | _tail] = flow.revisions
      assert Flows.check_required_fields(revision.definition, [:name]) == true
      definition = Map.delete(revision.definition, "name")
      assert_raise ArgumentError, fn -> Flows.check_required_fields(definition, [:name]) end
    end

    test "get_cached_flow/2 save the flow to cache returns a touple and flow", %{organization_id: organization_id} = attrs do
      [flow | _tail] = Flows.list_flows(%{filter: attrs})
      {:ok, loaded_flow} = Flows.get_cached_flow(organization_id, flow.uuid, %{uuid: flow.uuid})
      assert loaded_flow.nodes != nil

      # Next time Flow will be picked from cache
      Flows.delete_flow(flow)
      {:ok, loaded_flow_2} = Flows.get_cached_flow(organization_id, flow.uuid, %{uuid: flow.uuid})
      assert loaded_flow_2 == loaded_flow
    end

    test "update_cached_flow/1 will remove the keys and update the flows" do
      organization_id = Fixtures.get_org_id()
      [flow | _tail] = Flows.list_flows(%{filter: %{organization_id: organization_id}})
      {:ok, loaded_flow} = Flows.get_cached_flow(organization_id, flow.uuid, %{uuid: flow.uuid})
      Flows.update_flow(flow, %{:shortcode => "flow_new"})
      Flows.update_cached_flow(flow)
      {:ok, loaded_flow_new} = Flows.get_cached_flow(organization_id, flow.uuid, %{uuid: flow.uuid})
      assert loaded_flow.shortcode == flow.shortcode
      assert loaded_flow_new.shortcode != loaded_flow.shortcode
    end

    test "publish_flow/1 updates the latest flow revision status", %{organization_id: organization_id} = _attrs do
      flow = flow_fixture() |> Repo.preload([:revisions])

      # should set status of recent flow revision as "done"
      assert {:ok, %Flow{}} = Flows.publish_flow(flow)

      {:ok, revision} =
        FlowRevision
        |> Repo.fetch_by(%{flow_id: flow.id, revision_number: 0})

      assert revision.status == "done"

      [revision] = flow.revisions
      # should update the cached flow definition
      {:ok, loaded_flow} = Flows.get_cached_flow(organization_id, flow.uuid, %{uuid: flow.uuid})
      assert loaded_flow.definition == revision.definition

      # If a flow revision is already published
      # should reset previously published flow revision and set status of recent one as "done"
      new_definition = revision.definition |> Map.merge(%{"revision" => 2})
      Flows.create_flow_revision(new_definition)

      assert {:ok, %Flow{}} = Flows.publish_flow(flow)

      {:ok, revision} =
        FlowRevision
        |> Repo.fetch_by(%{flow_id: flow.id, revision_number: 0})

      assert revision.status == "done"

      # should update the cached flow definition
      {:ok, loaded_flow} = Flows.get_cached_flow(organization_id, flow.uuid, %{uuid: flow.uuid})
      assert loaded_flow.definition == new_definition
    end

    test "start_contact_flow/2 will setup the flow for a contact", attrs do
      [flow | _tail] = Flows.list_flows(%{filter: attrs})
      contact = Fixtures.contact_fixture(attrs)
      {:ok, flow} = Flows.start_contact_flow(flow, contact)
      first_action = hd(hd(flow.nodes).actions)

      assert {:ok, _message} =
               Repo.fetch_by(Message, %{uuid: first_action.uuid, contact_id: contact.id})
    end

    test "start_group_flow/2 will setup the flow for a group of contacts", attrs do
      [flow | _tail] = Flows.list_flows(%{filter: attrs})
      group = Fixtures.group_fixture()
      contact = Fixtures.contact_fixture()
      contact2 = Fixtures.contact_fixture()
      Groups.create_contact_group(%{group_id: group.id, contact_id: contact.id})
      Groups.create_contact_group(%{group_id: group.id, contact_id: contact2.id})
      {:ok, flow} = Flows.start_group_flow(flow, group)
      first_action = hd(hd(flow.nodes).actions)

      assert {:ok, _message} =
               Repo.fetch_by(Message, %{uuid: first_action.uuid, contact_id: contact.id})

      assert {:ok, _message} =
               Repo.fetch_by(Message, %{uuid: first_action.uuid, contact_id: contact2.id})
    end
  end
end
