defmodule GlificWeb.Schema.Query.LanguageTest do
  use GlificWeb.ConnCase, async: true

  setup do
    Glific.Seeds.seed()
    :ok
  end

  @query_1 """
  {
    languages {
      label
    }
  }
  """

  @query_2 """
  {
    language(id: $id) {
      label
    }
  }
  """
  @vars_2 """
  {
    "id": "2"
  }
  """

  defp make_api_call(query, vars \\ "") do
    conn = build_conn()
    conn = get conn, "/api", [query: query, variables: vars]

    json_response(conn, 200)
  end

  test "languages field returns list of languages" do
    assert make_api_call(@query_1) == %{
             "data" => %{
               "languages" => [
                 %{"label" => "English (United States)"},
                 %{"label" => "Hindi (India)"}
               ]
             }
           }

    assert make_api_call(@query_2, @vars_2) == %{
      "data" => %{
        "language" => %{"label" => "Hindi (India)" }
      }
    }

  end
end
