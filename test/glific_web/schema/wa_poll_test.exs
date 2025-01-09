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

    assert wa_poll["allowMultipleAnswer"] == true

    # Create a poll with duplicate options
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Duplicate Options Poll",
            "poll_content" =>
              "{\"options\":[{\"id\":0,\"name\":\"duplicate\",\"voters\":[],\"votes\":0},{\"id\":1,
            \"name\":\"duplicate\",\"voters\":[],\"votes\":0}],\"text\":\"poll with duplicates\"}"
          }
        }
      )

    assert {:ok, result_data} = result
    assert result_data |> get_in([:data, "CreateWaPoll"]) == nil

    # Create a poll with more than 12 options
    long_options =
      Enum.map(0..12, fn i ->
        %{"id" => i, "name" => "Option #{i}", "voters" => [], "votes" => 0}
      end)
      |> Jason.encode!()

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Too Many Options Poll",
            "poll_content" =>
              "{\"options\":#{long_options},\"text\":\"poll with too many options\"}"
          }
        }
      )

    assert {:ok, result_data} = result
    assert result_data |> get_in([:data, "CreateWaPoll"]) == nil
  end
end
