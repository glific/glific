defmodule GlificWeb.Schema.SheetTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures
  }

  load_gql(:count, GlificWeb.Schema, "assets/gql/sheets/count.gql")

  test "count returns the number of sheets", %{staff: user} = attrs do
    Fixtures.sheet_fixture(attrs)
    {:ok, query_data} = auth_query_gql_by(:count, user)
  end
end
