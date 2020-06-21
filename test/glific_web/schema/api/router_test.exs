defmodule GlificWeb.RouterTest do
  use GlificWeb.ConnCase, async: true

  setup do
    lang = Glific.Seeds.seed_language()
    Glific.Seeds.seed_tag(lang)
    :ok
  end

  # lets do a simple tags listing to test the forward call on the normal channel
  describe "test tags via /api and http" do
    test "gets a list of tags" do
      query = """
      query listTags {
        tags {
          id
          label
          language {
            id
            label
          }
        }
      }
      """

      variables = %{}

      response =
        build_conn()
        |> post("/api", %{query: query, variables: variables})

      response = json_response(response, 200)
      tags = get_in(response, ["data", "tags"])
      assert length(tags) > 0

      # grab the graphiql end point to ensure it is present and running
      response =
        build_conn()
        |> post("/graphiql", %{query: query, variables: variables})

      gql = json_response(response, 200)
      gql_tags = get_in(gql, ["data", "tags"])
      assert tags == gql_tags
    end

    test "test secure endpoints and ensure we get an error while we figure out authorization" do
      response =
        build_conn()
        |> post("/secure/api", %{query: "", variables: %{}})

      assert response.status == 401

      response =
        build_conn()
        |> post("/secure/graphiql", %{query: "", variables: %{}})

      assert response.status == 401
    end
  end
end
