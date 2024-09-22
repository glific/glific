defmodule Glific.FilesearchTest do
  @moduledoc """
  Tests for public filesearch APIs
  """

  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  load_gql(
    :create_vector_store,
    GlificWeb.Schema,
    "assets/gql/filesearch/create_vector_store.gql"
  )

  @tag :vs_api
  test "valid create vector_store", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://api.openai.com/v1/vector_stores"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "vs_123"
          }
        }
    end)

    result =
      auth_query_gql_by(:create_vector_store, user,
        variables: %{
          "input" => %{
            "name" => "vs_1"
          }
        }
      )

    assert {:ok, query_data} = result
    assert query_data.data["createVectorStore"]["vectorStore"]["name"] == "vs_1"
  end

  @tag :vs_api
  test "create vector_store failed due to api failure", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://api.openai.com/v1/vector_stores"} ->
        %Tesla.Env{
          status: 500,
          body: %{}
        }
    end)

    result =
      auth_query_gql_by(:create_vector_store, user,
        variables: %{
          "input" => %{
            "name" => "vs_1"
          }
        }
      )

    assert {:ok, query_data} = result
    assert length(query_data.errors) == 1
  end
end
