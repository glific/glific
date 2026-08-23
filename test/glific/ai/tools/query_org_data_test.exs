defmodule Glific.AI.Tools.QueryOrgDataTest do
  use Glific.DataCase, async: false

  alias Glific.AI.Tool.Context
  alias Glific.AI.Tools.QueryOrgData
  alias Glific.Fixtures
  alias Glific.Users.User

  setup %{organization_id: organization_id} do
    context = %Context{
      organization_id: organization_id,
      user: %User{id: 1},
      request_id: "req-query-org-data",
      step_index: 0
    }

    %{context: context, organization_id: organization_id}
  end

  describe "behaviour" do
    test "declares its identity" do
      assert QueryOrgData.name() == "query_org_data"
      assert is_binary(QueryOrgData.description())
    end

    test "requires :manager — ChatbotDiagnose.run/3 is org-scoped but not permission-scoped" do
      assert QueryOrgData.required_role() == :manager
    end

    test "the table parameter is a closed enum built from ChatbotDiagnose.tables/0" do
      [table: opts, fields: _, filters: _, limit: _, time_range: _] = QueryOrgData.parameters()
      assert {:in, tables} = opts[:type]
      assert Enum.sort(tables) == Enum.sort(Glific.ChatbotDiagnose.tables())
    end
  end

  describe "run/2" do
    test "returns rows for the acting organisation, limited to the requested fields", %{
      context: context,
      organization_id: organization_id
    } do
      contact = Fixtures.contact_fixture(%{organization_id: organization_id})

      assert {:ok, rows} =
               QueryOrgData.run(
                 %{"table" => "contacts", "fields" => ["id", "name"], "limit" => 50},
                 context
               )

      assert Enum.any?(rows, &(&1.id == contact.id))

      Enum.each(rows, fn row ->
        assert Map.has_key?(row, :id)
        assert Map.has_key?(row, :name)
        refute Map.has_key?(row, :phone)
      end)
    end

    test "does not leak another organisation's rows", %{context: context} do
      other_org = Fixtures.organization_fixture(%{shortcode: "queryorgdata-other"})
      other_contact = Fixtures.contact_fixture(%{organization_id: other_org.id})

      assert {:ok, rows} =
               QueryOrgData.run(%{"table" => "contacts", "fields" => ["id"]}, context)

      refute Enum.any?(rows, &(&1.id == other_contact.id))
    end

    test "applies equality filters", %{context: context, organization_id: organization_id} do
      contact = Fixtures.contact_fixture(%{organization_id: organization_id})

      assert {:ok, rows} =
               QueryOrgData.run(
                 %{
                   "table" => "contacts",
                   "fields" => ["id", "phone"],
                   "filters" => %{"phone" => contact.phone}
                 },
                 context
               )

      assert Enum.map(rows, & &1.id) == [contact.id]
    end

    test "returns an error when table is missing", %{context: context} do
      assert {:error, message} = QueryOrgData.run(%{}, context)
      assert message =~ "required"
    end

    test "returns an error for a table string outside the registry, as defence in depth", %{
      context: context
    } do
      assert {:error, message} =
               QueryOrgData.run(%{"table" => "not_a_real_table"}, context)

      assert message =~ "Unknown table"
    end
  end
end
