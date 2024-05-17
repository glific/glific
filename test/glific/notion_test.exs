defmodule Glific.NotionTest do
  @moduledoc """
  Tests for Glific.Notion
  """
  use Glific.DataCase
  alias Glific.{Notion, Fixtures}

  @tag :notion
  test "Failed create_database_entry due to fetch database error" do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 404,
          body: %{
            object: "error"
          }
        }
    end)

    registration = Fixtures.registration_fixture()
    assert {:error, _} = Notion.create_database_entry(registration)
  end

  @tag :notion
  test "Failed create_database_entry due to create page error" do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            object: "database",
            properties: %{}
          }
        }

      %{method: :post} ->
        %Tesla.Env{
          status: 404,
          body: %{
            object: "error"
          }
        }
    end)

    registration = Fixtures.registration_fixture()
    assert {:error, _} = Notion.create_database_entry(registration)
  end

  @tag :notion
  test "Valid create_database_entry" do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            object: "database",
            properties: %{}
          }
        }

      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            object: "page",
            properties: %{}
          }
        }
    end)

    registration = Fixtures.registration_fixture()
    assert {:ok, _} = Notion.create_database_entry(registration)
  end
end
