defmodule Glific.FilesearchTest do
  @moduledoc """
  Tests for public filesearch APIs
  """

  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  load_gql(:create_assistant, GlificWeb.Schema, "assets/gql/filesearch/create_assistant.gql")

  @tag :asst_api
  test "valid create assistant", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://api.openai.com/v1/assistants"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            id: "ass_123"
          }
        }
    end)

    result =
      auth_query_gql_by(:create_assistant, user,
        variables: %{
          "input" => %{
            "name" => "assistant_1",
            "model" => "gpt-4o"
          }
        }
      )

    assert {:ok, _query_data} = result |> IO.inspect()
  end
end
