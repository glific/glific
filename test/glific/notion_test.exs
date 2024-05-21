defmodule Glific.NotionTest do
  @moduledoc """
  Tests for Glific.Notion
  """
  use Glific.DataCase
  alias Glific.{Fixtures, Notion}

  @tag :notion
  test "Failed create_database_entry due to create page error" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 404,
          body: %{
            object: "error"
          }
        }
    end)

    registration = Fixtures.registration_fixture()

    assert {:error, _} =
             Notion.init_table_properties(registration)
             |> Notion.create_database_entry()
  end

  @tag :notion
  test "Valid create_database_entry" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            object: "page",
            id: "page_id",
            properties: %{}
          }
        }
    end)

    registration = Fixtures.registration_fixture()

    assert {:ok, _} =
             Notion.init_table_properties(registration)
             |> Notion.create_database_entry()
  end

  @tag :notion
  test "Failed update_database_row due to fetch database error" do
    Tesla.Mock.mock(fn
      %{method: :patch} ->
        %Tesla.Env{
          status: 404,
          body: %{
            object: "error"
          }
        }
    end)

    registration = Fixtures.registration_fixture()

    assert {:error, _} =
             Notion.update_table_properties(registration)
             |> then(&Notion.update_database_entry("page_id", &1))
  end

  @tag :notion
  test "Failed create_database_entry due to update page error" do
    Tesla.Mock.mock(fn
      %{method: :patch} ->
        %Tesla.Env{
          status: 404,
          body: %{
            object: "error"
          }
        }
    end)

    registration = Fixtures.registration_fixture()

    assert {:error, _} =
             Notion.update_table_properties(registration)
             |> then(&Notion.update_database_entry("page_id", &1))
  end

  @tag :notion
  test "Valid update_database_entry" do
    Tesla.Mock.mock(fn
      %{method: :patch} ->
        %Tesla.Env{
          status: 200,
          body: %{
            object: "page",
            id: "page_id",
            properties: %{}
          }
        }
    end)

    registration = Fixtures.registration_fixture()

    assert {:ok, _} =
             Notion.update_table_properties(registration)
             |> then(&Notion.update_database_entry("page_id", &1))
  end
end
