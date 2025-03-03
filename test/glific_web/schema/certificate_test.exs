defmodule GlificWeb.Schema.CertificateTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  load_gql(:create, GlificWeb.Schema, "assets/gql/certificates/create.gql")

  @tag :cert
  test "create certificate template failures", %{user: user} do
    result = auth_query_gql_by(:create, user, variables: %{})
    assert {:ok, query_data} = result

    # No input
    assert length(query_data.errors) == 1

    # no required params
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => ""
          }
        }
      )

    assert {:ok, query_data} = result
    assert length(query_data.errors) == 1

    # invalid url
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "slides",
            "url" => "slides url"
          }
        }
      )

    assert {:ok, %{errors: [%{message: "Invalid Template url"}]}} = result

    # invalid type
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "slides",
            "url" => "https://example.com",
            "type" => "pdf"
          }
        }
      )

    assert {:ok, %{errors: [%{message: "Template of type pdf not supported yet"}]}} = result

    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 401
        }
    end)

    # Not a valid google slide
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "slides",
            "url" => "https://example.com"
          }
        }
      )

    assert {:ok, %{errors: [%{message: "Template url not a valid Google Slides"}]}} = result

    # Not a public url
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "slides",
            "url" => "https://docs.google.com/presentation/d/id/edit#slide=id.p"
          }
        }
      )

    assert {:ok, %{errors: [%{message: "Invalid Template url"}]}} = result
  end
end
