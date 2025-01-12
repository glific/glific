defmodule GlificWeb.Schema.WAPollTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{Repo, WaGroup.WaPoll}

  load_gql(:create, GlificWeb.Schema, "assets/gql/wa_poll/create.gql")
  load_gql(:fetch, GlificWeb.Schema, "assets/gql/wa_poll/fetch.gql")
  load_gql(:copy, GlificWeb.Schema, "assets/gql/wa_poll/copy.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/wa_poll/delete.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/wa_poll/list.gql")
  load_gql(:count, GlificWeb.Schema, "assets/gql/wa_poll/count.gql")

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

    # by default the allow multiple answers should be false
    assert wa_poll["allowMultipleAnswer"] == false

    # allow multiple answer should be true
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

  test "count wa_polls with and without filters", %{manager: user} do
    for i <- 1..3 do
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Test Poll #{i}",
            "poll_content" =>
              "{\"options\":[{\"id\":0,\"name\":\"option1\",\"voters\":[],\"votes\":0}],\"text\":\"poll #{i}\"}",
            "allow_multiple_answer" => i == 3
          }
        }
      )
    end

    # Count all polls without filters
    {:ok, query_data} = auth_query_gql_by(:count, user, variables: %{})
    total_count = query_data |> get_in([:data, "countWaPolls"])
    assert total_count == 3

    # Filter polls by label
    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{
          "filter" => %{"label" => "Test Poll 1"}
        }
      )

    filtered_count = query_data |> get_in([:data, "countWaPolls"])
    assert filtered_count == 1

    # Filter polls by `allow_multiple_answer`
    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{
          "filter" => %{"allow_multiple_answer" => true}
        }
      )

    filtered_count = query_data |> get_in([:data, "countWaPolls"])
    assert filtered_count == 1

    # Fetch polls with invalid filter
    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{
          "filter" => %{"label" => "Nonexistent Poll"}
        }
      )

    filtered_count = query_data |> get_in([:data, "countWaPolls"])
    assert filtered_count == 0
  end

  test "list wa_polls with and without filters", %{manager: user} do
    for i <- 1..3 do
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Test Poll #{i}",
            "poll_content" =>
              "{\"options\":[{\"id\":0,\"name\":\"option1\",\"voters\":[],\"votes\":0}],\"text\":\"poll #{i}\"}",
            "allow_multiple_answer" => i == 3
          }
        }
      )
    end

    # Fetch all polls without filters
    result = auth_query_gql_by(:list, user, variables: %{})
    assert {:ok, query_data} = result

    polls = query_data |> get_in([:data, "waPolls"])
    assert length(polls) == 3

    # Filter polls by label
    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"label" => "Test Poll 1"}
        }
      )

    assert {:ok, query_data} = result
    filtered_polls = query_data |> get_in([:data, "waPolls"])
    assert length(filtered_polls) == 1
    assert hd(filtered_polls)["label"] == "Test Poll 1"

    # Filter polls by `allow_multiple_answer`
    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"allow_multiple_answer" => true}
        }
      )

    assert {:ok, query_data} = result
    filtered_polls = query_data |> get_in([:data, "waPolls"])
    assert length(filtered_polls) == 1
    assert hd(filtered_polls)["label"] == "Test Poll 3"

    # Fetch polls with invalid filter
    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"label" => "Nonexistent Poll"}
        }
      )

    assert {:ok, query_data} = result
    filtered_polls = query_data |> get_in([:data, "waPolls"])
    assert Enum.empty?(filtered_polls) == true
  end

  test "copy an existing wa_poll", %{manager: user} do
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Poll to Copy",
            "poll_content" =>
              "{\"options\":[{\"id\":0,\"name\":\"opt1\",\"voters\":[],\"votes\":0}],\"text\":\"poll to copy\"}"
          }
        }
      )

    assert {:ok, query_data} = result
    wa_poll = query_data |> get_in([:data, "CreateWaPoll", "waPoll"])

    result =
      auth_query_gql_by(:copy, user,
        variables: %{
          "copyWaPollId" => wa_poll["id"],
          "input" => %{"label" => "Copied Poll"}
        }
      )

    assert {:ok, query_data} = result
    copied_wa_poll = query_data |> get_in([:data, "copyWaPoll", "waPoll"])
    assert copied_wa_poll["label"] == "Copied Poll"
  end

  test "delete an existing wa_poll and possible scenarios", %{manager: user} do
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Poll to Delete",
            "poll_content" =>
              "{\"options\":[{\"id\":0,\"name\":\"delete_opt\",\"voters\":[],\"votes\":0}],\"text\":\"poll to delete\"}"
          }
        }
      )

    assert {:ok, query_data} = result
    wa_poll = query_data |> get_in([:data, "CreateWaPoll", "waPoll"])

    result = auth_query_gql_by(:delete, user, variables: %{"deleteWaPollId" => wa_poll["id"]})

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteWaPoll", "errors"]) == nil
    result = auth_query_gql_by(:delete, user, variables: %{"deleteWaPollId" => 123_444})
    assert {:ok, query_data} = result

    message =
      get_in(query_data, [:data, "deleteWaPoll", "errors", Access.at(0), "message"])

    assert message == "Resource not found"
  end
end
