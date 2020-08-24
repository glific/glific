defmodule Glific.FLowsTest do
  use Glific.DataCase

  alias Glific.{
    Flows,
    Flows.Flow,
    Flows.FlowRevision
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

    def flow_fixture(attrs \\ %{}) do
      {:ok, flow} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Flows.create_flow()

      flow
    end

    test "list_flows/0 returns all flows" do
      flow = flow_fixture()
      assert Enum.filter(Flows.list_flows(), fn fl -> fl.name == flow.name end) == [flow]
    end

    test "list_flows/1 returns flows filtered by keyword" do
      f0 = flow_fixture(@valid_attrs)
      _f1 = flow_fixture(@valid_more_attrs)

      flows = Flows.list_flows(%{filter: %{keyword: "test_keyword"}})
      assert flows == [f0]

      flows = Flows.list_flows(%{filter: %{keyword: "wrong_keyword"}})
      assert flows == []

      flows = Flows.list_flows(%{filter: %{wrong_filter: "test"}})
      assert length(flows) >= 2
    end

    test "count_flows/0 returns count of all flows" do
      flow_count = Repo.aggregate(Flow, :count)

      _ = flow_fixture()
      assert Flows.count_flows() == flow_count + 1

      _ = flow_fixture(@valid_more_attrs)
      assert Flows.count_flows() == flow_count + 2

      assert Flows.count_flows(%{filter: %{name: "Help Workflow"}}) == 1
    end

    test "get_flow!/1 returns the flow with given id" do
      flow = flow_fixture()
      assert Flows.get_flow!(flow.id) == flow
    end

    test "create_flow/1 with valid data creates a flow" do
      assert {:ok, %Flow{} = flow} = Flows.create_flow(@valid_attrs)
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
      assert {:ok, %Flow{} = flow} = Flows.create_flow(@valid_attrs)
      flow = Glific.Repo.preload(flow, [:revisions])
      assert flow.name == @valid_attrs.name
      assert flow.flow_type == @valid_attrs.flow_type
      assert [revision] = flow.revisions
      assert revision.status == "done"
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

    test "check_required_fields/1 check the required field in the json file" do
      [flow | _tail] = Flows.list_flows()
      flow = Glific.Repo.preload(flow, [:revisions])
      [revision | _tail] = flow.revisions
      assert Flows.check_required_fields(revision.definition, [:name]) == true
      definition = Map.delete(revision.definition, "name")
      assert_raise ArgumentError, fn -> Flows.check_required_fields(definition, [:name]) end
    end

    test "get_cached_flow/2 save the flow to cache returns a touple and flow" do
      [flow | _tail] = Flows.list_flows()
      {:ok, loaded_flow} = Flows.get_cached_flow(flow.uuid, %{uuid: flow.uuid})
      assert loaded_flow.nodes != nil

      # Next time Flow will be picked from cache
      Flows.delete_flow(flow)
      {:ok, loaded_flow_2} = Flows.get_cached_flow(flow.uuid, %{uuid: flow.uuid})
      assert loaded_flow_2 == loaded_flow
    end

    test "update_cached_flow/1 will remove the keys and update the flows" do
      [flow | _tail] = Flows.list_flows()
      {:ok, loaded_flow} = Flows.get_cached_flow(flow.uuid, %{uuid: flow.uuid})
      Flows.update_flow(flow, %{:shortcode => "flow_new"})
      Flows.update_cached_flow(flow.uuid)
      {:ok, loaded_flow_new} = Flows.get_cached_flow(flow.uuid, %{uuid: flow.uuid})
      assert loaded_flow.shortcode == flow.shortcode
      assert loaded_flow_new.shortcode != loaded_flow.shortcode
    end

    test "done_edit_flow/1 updates the latest flow revision status" do
      flow = flow_fixture()
      assert {:ok, %Flow{}} = Flows.done_edit_flow(flow)

      {:ok, revision} =
        Flows.FlowRevision
        |> Repo.fetch_by(%{flow_id: flow.id, revision_number: 0})

      assert revision.status == "done"
    end
  end
end
