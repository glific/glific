defmodule GlificWeb.Schema.ConsultingHourTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Seeds.SeedsDev
  }

  setup do
    SeedsDev.seed_organizations()
  end

  load_gql(:by_id, GlificWeb.Schema, "assets/gql/consulting_hour/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/consulting_hour/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/consulting_hour/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/consulting_hour/delete.gql")

  test "create a consulting hour entry and test possible scenarios and errors", %{manager: user} do
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "participants" => "Adam",
            "organizationId" => 1,
            "organizationName" => "Glific",
            "staff" => "Adelle Cavin",
            "content" => "GCS issue",
            "when" => "2021-03-08T08:22:51Z",
            "duration" => 10,
            "is_billable" => true
          }
        }
      )

    IO.inspect(result)

    # assert {:ok, query_data} = result
    # label = get_in(query_data, [:data, "createTag", "tag", "label"])
    # assert label == "Test Tag"

    # # try creating the same tag twice
    # _ =
    #   auth_query_gql_by(:create, user,
    #     variables: %{
    #       "input" => %{
    #         "label" => "Klingon",
    #         "shortcode" => "klingon",
    #         "languageId" => language_id
    #       }
    #     }
    #   )

    # result =
    #   auth_query_gql_by(:create, user,
    #     variables: %{
    #       "input" => %{
    #         "label" => "Klingon",
    #         "shortcode" => "klingon",
    #         "languageId" => language_id
    #       }
    #     }
    #   )

    # assert {:ok, query_data} = result

    # message = get_in(query_data, [:data, "createTag", "errors", Access.at(0), "message"])
    # assert message == "has already been taken"
  end
end
