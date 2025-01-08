defmodule GlificWeb.Schema.WAPollTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{Repo, WaGroup.WaPoll}

  load_gql(:create, GlificWeb.Schema, "assets/gql/wa_poll/create.gql")
  load_gql(:fetch, GlificWeb.Schema, "assets/gql/wa_poll/fetch.gql")

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
    assert wa_poll["onlyOne"] == false

    # only one should be true
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Test only one",
            "poll_content" =>
              "{\"options\":[{\"id\":0,\"name\":\"okay\",\"voters\":[],\"votes\":0},{\"id\":1,
              \"name\":\"huh\",\"voters\":[],\"votes\":0}],\"text\":\"testing poll\"}",
            "only_one" => true
          }
        }
      )

    assert {:ok, query_data} = result
    wa_poll = query_data |> get_in([:data, "CreateWaPoll", "waPoll"])

    assert wa_poll["onlyOne"] == true
  end

  test "fetch the wa_poll using id", %{manager: user} do
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
    label = wa_poll["label"]

    {:ok, wa_poll} =
      Repo.fetch_by(WaPoll, %{label: label, organization_id: user.organization_id})

    result = auth_query_gql_by(:fetch, user, variables: %{"waPollId" => wa_poll.id})

    assert {:ok, query_data} = result
    fetched_wa_poll = query_data |> get_in([:data, "waPoll", "waPoll"])
    assert fetched_wa_poll["label"] == label
  end
end
