defmodule GlificWeb.Schema.WAPollTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  load_gql(:create, GlificWeb.Schema, "assets/gql/wa_poll/create.gql")

  test "create a poll and test possible scenarios", %{manager: user} do
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Test Poll",
            "poll_content" =>
              "{\"options\":[{\"id\":0,\"name\":\"okay\",\"voters\":[],\"votes\":0},{\"id\":1,
              \"name\":\"huh\",\"voters\":[],\"votes\":0}],\"text\":\"testing poll\"}"
          }
        }
      )

    assert {:ok, query_data} = result
    wa_poll = query_data |> get_in([:data, "CreateWaPoll", "waPoll"])

    assert wa_poll["label"] == "Test Poll"

    # by default the only one should be false
    assert wa_poll["allowMultipleAnswer"] == false

    # only one should be true
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Test only one",
            "poll_content" =>
              "{\"options\":[{\"id\":0,\"name\":\"okay\",\"voters\":[],\"votes\":0},{\"id\":1,
              \"name\":\"huh\",\"voters\":[],\"votes\":0}],\"text\":\"testing poll\"}",
            "allow_multiple_answer" => true
          }
        }
      )

    assert {:ok, query_data} = result
    wa_poll = query_data |> get_in([:data, "CreateWaPoll", "waPoll"])

    assert wa_poll["onlyOne"] == true
  end
end
