defmodule Glific.FLowsTest do
  use Glific.DataCase

  alias Glific.{Flows, Flows.Flow, Settings.Language}

  describe "flows" do
    # language id needs to be added dynamically for all the below actions
    @valid_attrs %{
      name: "Test Flow",
      shortcode: "test_short_code",
      flow_type: :message,
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
      language = Repo.fetch_by(Language, %{label: "Hindi"}) |> elem(1)

      {:ok, flow} =
        attrs
        |> Map.put(:language_id, language.id)
        |> Enum.into(@valid_attrs)
        |> Flows.create_flow()

      flow
    end

    test "list_flows/0 returns all flows" do
      flow = flow_fixture()
      assert Enum.filter(Flows.list_flows(), fn fl -> fl.name == flow.name end) == [flow]
    end

    test "get_flow!/1 returns the flow with given id" do
      flow = flow_fixture()
      assert Flows.get_flow!(flow.id) == flow
    end

    test "create_flow/1 with valid data creates a flow" do
      language = Repo.fetch_by(Language, %{label: "Hindi"}) |> elem(1)
      attrs = Map.merge(@valid_attrs, %{language_id: language.id})
      assert {:ok, %Flow{} = flow} = Flows.create_flow(attrs)
      assert flow.name == @valid_attrs.name
      assert flow.flow_type == @valid_attrs.flow_type
      assert flow.shortcode == @valid_attrs.shortcode
      assert flow.language_id == language.id
    end

    test "create_flow/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Flows.create_flow(@invalid_attrs)
    end

    test "create_flow/1 will have a default revision" do
      language = Repo.fetch_by(Language, %{label: "Hindi"}) |> elem(1)
      attrs = Map.merge(@valid_attrs, %{language_id: language.id})
      assert {:ok, %Flow{} = flow} = Flows.create_flow(attrs)
      flow = Glific.Repo.preload(flow, [:revisions])
      assert flow.name == @valid_attrs.name
      assert flow.flow_type == @valid_attrs.flow_type
      assert [revision] = flow.revisions
      assert length(flow.revisions) > 0
    end

    test "update_flow/2 with valid data updates the flow" do
      flow = flow_fixture()
      language = Repo.fetch_by(Language, %{label: "Hindi"}) |> elem(1)
      attrs = Map.merge(@update_attrs, %{language_id: language.id})
      assert {:ok, %Flow{} = flow} = Flows.update_flow(flow, attrs)
      assert flow.name == @update_attrs.name
      assert flow.language_id == language.id
    end

    test "update_flow/2 with invalid data returns error changeset" do
      flow = flow_fixture()
      assert {:error, %Ecto.Changeset{}} = Flows.update_flow(flow, @invalid_attrs)
      assert flow == Flows.get_flow!(flow.id)
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
  end
end
