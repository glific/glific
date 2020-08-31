defmodule GlificWeb.RouterTest do
  use GlificWeb.ConnCase, async: true

  alias Glific.{
    Fixtures,
    Repo,
    Seeds.SeedsDev,
    Users.User
  }

  @password "secret1234"
  @valid_params %{
    "user" => %{"phone" => "+919820198765", "name" => "Jane Doe", "password" => @password}
  }

  setup %{conn: conn, organization_id: organization_id} do
    SeedsDev.seed_tag()

    contact = Fixtures.contact_fixture()

    _user =
      %User{}
      |> User.changeset(%{
        phone: @valid_params["user"]["phone"],
        name: @valid_params["user"]["name"],
        password: @password,
        password_confirmation: @password,
        contact_id: contact.id,
        organization_id: organization_id
      })
      |> Repo.insert!()

    authed_conn = post(conn, Routes.api_v1_session_path(conn, :create, @valid_params))
    :timer.sleep(100)

    {:ok, access_token: authed_conn.private[:api_access_token]}
  end

  # lets do a simple tags listing to test the forward call on the normal channel
  describe "test tags via /api and http" do
    test "gets a list of tags", %{conn: conn, access_token: token} do
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
        conn
        |> Plug.Conn.put_req_header("authorization", token)
        |> post("/api", %{query: query, variables: variables})

      response = json_response(response, 200)
      tags = get_in(response, ["data", "tags"])
      assert length(tags) > 0

      # grab the graphiql end point to ensure it is present and running
      response =
        conn
        |> Plug.Conn.put_req_header("authorization", token)
        |> post("/graphiql", %{query: query, variables: variables})

      gql = json_response(response, 200)
      gql_tags = get_in(gql, ["data", "tags"])
      assert tags == gql_tags
    end

    test "test  endpoints and ensure we get an error when not authenricated", %{conn: conn} do
      response =
        conn
        |> post("/api", %{query: "", variables: %{}})

      assert response.status == 401

      response =
        conn
        |> post("/graphiql", %{query: "", variables: %{}})

      assert response.status == 401
    end
  end
end
