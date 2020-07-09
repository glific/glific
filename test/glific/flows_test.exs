defmodule Glific.FlowsTest do
  use Glific.DataCase

  alias Glific.Flows

  describe "flows" do
    alias Glific.Flows.Flow

    @valid_attrs %{}
    @update_attrs %{}
    @invalid_attrs %{}

    def flow_fixture(attrs \\ %{}) do
      {:ok, flow} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Flows.create_flow()

      flow
    end

    test "list_flows/0 returns all flows" do
      flow = flow_fixture()
      assert Flows.list_flows() == [flow]
    end

    test "get_flow!/1 returns the flow with given id" do
      flow = flow_fixture()
      assert Flows.get_flow!(flow.id) == flow
    end

    test "create_flow/1 with valid data creates a flow" do
      assert {:ok, %Flow{} = flow} = Flows.create_flow(@valid_attrs)
    end

    test "create_flow/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Flows.create_flow(@invalid_attrs)
    end

    test "update_flow/2 with valid data updates the flow" do
      flow = flow_fixture()
      assert {:ok, %Flow{} = flow} = Flows.update_flow(flow, @update_attrs)
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
  end
end
