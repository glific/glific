defmodule Glific.AI.Tools.DescribeTableTest do
  use Glific.DataCase, async: true

  alias Glific.AI.Tool.Context
  alias Glific.AI.Tools.DescribeTable
  alias Glific.Users.User

  setup %{organization_id: organization_id} do
    context = %Context{
      organization_id: organization_id,
      user: %User{id: 1},
      request_id: "req-describe-table",
      step_index: 0
    }

    %{context: context}
  end

  describe "behaviour" do
    test "declares its identity" do
      assert DescribeTable.name() == "describe_table"
      assert is_binary(DescribeTable.description())
      assert DescribeTable.required_role() == :staff
    end

    test "the table parameter is a closed enum built from ChatbotDiagnose.tables/0" do
      [table: opts] = DescribeTable.parameters()
      assert {:in, tables} = opts[:type]
      assert "contacts" in tables
      assert Enum.sort(tables) == Enum.sort(Glific.ChatbotDiagnose.tables())
    end
  end

  describe "run/2" do
    test "returns the allow-listed fields for a known table", %{context: context} do
      assert {:ok, %{table: "contacts", fields: fields}} =
               DescribeTable.run(%{"table" => "contacts"}, context)

      assert "id" in fields
      assert "phone" in fields
      assert Enum.all?(fields, &is_binary/1)
    end

    test "returns an error for an unknown table", %{context: context} do
      assert {:error, message} = DescribeTable.run(%{"table" => "not_a_real_table"}, context)
      assert message =~ "Unknown table"
    end

    test "returns an error when table is missing", %{context: context} do
      assert {:error, message} = DescribeTable.run(%{}, context)
      assert message =~ "required"
    end
  end
end
