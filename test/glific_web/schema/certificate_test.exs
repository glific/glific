defmodule GlificWeb.Schema.CertificateTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  load_gql(:create, GlificWeb.Schema, "assets/gql/certificates/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/certificates/update.gql")
  load_gql(:get, GlificWeb.Schema, "assets/gql/certificates/by_id.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/certificates/list.gql")
  load_gql(:count, GlificWeb.Schema, "assets/gql/certificates/count.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/certificates/delete.gql")

  @tag :cert
  test "create certificate template failures", %{user: user} do
    result = auth_query_gql_by(:create, user, variables: %{})
    assert {:ok, query_data} = result

    # No input
    assert length(query_data.errors) == 2

    # no required params
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => ""
          }
        }
      )

    assert {:ok,
            %{
              data: %{
                "CreateCertificateTemplate" => %{
                  "errors" => [
                    %{"message" => "Label: can't be blank"},
                    %{"message" => "Url: can't be blank"}
                  ]
                }
              }
            }} =
             result

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

    assert {:ok,
            %{
              data: %{
                "CreateCertificateTemplate" => %{
                  "errors" => [
                    %{"message" => "Url: Invalid Template url"}
                  ]
                }
              }
            }} =
             result

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

    assert {:ok,
            %{
              errors: [
                %{
                  message:
                    "Argument \"input\" has invalid value $input.\nIn field \"type\": Expected type \"CertificateTemplateTypeEnum\", found \"pdf\"."
                }
              ]
            }} =
             result

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

    assert {:ok,
            %{
              data: %{
                "CreateCertificateTemplate" => %{
                  "errors" => [
                    %{"message" => "Url: Template url not a valid Google Slides"}
                  ]
                }
              }
            }} =
             result

    # Need to check if scopes are there, instead of public
    # result =
    #   auth_query_gql_by(:create, user,
    #     variables: %{
    #       "input" => %{
    #         "label" => "slides",
    #         "url" => "https://docs.google.com/presentation/d/id/edit#slide=id.p"
    #       }
    #     }
    #   )

    # assert {:ok,
    #         %{
    #           data: %{
    #             "CreateCertificateTemplate" => %{
    #               "errors" => [
    #                 %{"message" => "Url: Invalid Template url"}
    #               ]
    #             }
    #           }
    #         }} =
    #          result

    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200
        }
    end)

    # Other validations
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => String.duplicate("slides", 100),
            "url" => "https://docs.google.com/presentation/d/id/edit#slide=id.p"
          }
        }
      )

    assert {:ok,
            %{
              data: %{
                "CreateCertificateTemplate" => %{
                  "errors" => [
                    %{"message" => "Label: should be at most 40 character(s)"}
                  ]
                }
              }
            }} =
             result

    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200
        }
    end)

    # Other validations
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "slides",
            "url" => "https://docs.google.com/presentation/d/id/edit#slide=id.p",
            "description" => String.duplicate("lorum ipsum", 250)
          }
        }
      )

    assert {:ok,
            %{
              data: %{
                "CreateCertificateTemplate" => %{
                  "errors" => [
                    %{"message" => "Description: should be at most 150 character(s)"}
                  ]
                }
              }
            }} =
             result
  end

  @tag :cert
  test "create certificate template success", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200
        }
    end)

    # Other validations
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "slides",
            "url" => "https://docs.google.com/presentation/d/id/edit#slide=id.p",
            "description" => "lorum ipsum"
          }
        }
      )

    assert {:ok,
            %{
              data: %{
                "CreateCertificateTemplate" => %{
                  "certificateTemplate" => %{"id" => _}
                }
              }
            }} =
             result
  end

  @tag :cert
  test "update certificate template success", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200
        }
    end)

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "slides",
            "url" => "https://docs.google.com/presentation/d/id/edit#slide=id.p",
            "description" => "lorum ipsum"
          }
        }
      )

    assert {:ok,
            %{
              data: %{
                "CreateCertificateTemplate" => %{
                  "certificateTemplate" => %{"id" => id}
                }
              }
            }} =
             result

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => id,
          "input" => %{
            "label" => "slides2",
            "url" => "https://docs.google.com/presentation/d/id2/edit#slide=id.p"
          }
        }
      )

    assert {:ok,
            %{
              data: %{
                "UpdateCertificateTemplate" => %{
                  "certificateTemplate" => %{
                    "id" => ^id,
                    "label" => "slides2",
                    "url" => "https://docs.google.com/presentation/d/id2/edit#slide=id.p"
                  }
                }
              }
            }} =
             result
  end

  @tag :cert
  test "update certificate template failure", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200
        }
    end)

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "slides",
            "url" => "https://docs.google.com/presentation/d/id/edit#slide=id.p",
            "description" => "lorum ipsum"
          }
        }
      )

    assert {:ok,
            %{
              data: %{
                "CreateCertificateTemplate" => %{
                  "certificateTemplate" => %{"id" => _id}
                }
              }
            }} =
             result

    # Tesla.Mock.mock(fn
    #   %{method: :get} ->
    #     %Tesla.Env{
    #       status: 400
    #     }
    # end)

    # result =
    #   auth_query_gql_by(:update, user,
    #     variables: %{
    #       "id" => id,
    #       "input" => %{
    #         "label" => "slides2",
    #         "url" => "https://docs.google.com/presentation/d/id2/edit#slide=id.p"
    #       }
    #     }
    #   )

    # assert {:ok,
    #         %{
    #           data: %{
    #             "UpdateCertificateTemplate" => %{
    #               "errors" => [
    #                 %{"message" => "Url: Invalid Template url"}
    #               ]
    #             }
    #           }
    #         }} =
    #          result
  end

  @tag :cert
  test "get certificate template", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200
        }
    end)

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "slides",
            "url" => "https://docs.google.com/presentation/d/id/edit#slide=id.p",
            "description" => "lorum ipsum"
          }
        }
      )

    assert {:ok,
            %{
              data: %{
                "CreateCertificateTemplate" => %{
                  "certificateTemplate" => %{"id" => id}
                }
              }
            }} =
             result

    result =
      auth_query_gql_by(:get, user,
        variables: %{
          "id" => id
        }
      )

    assert {:ok,
            %{
              data: %{
                "CertificateTemplate" => %{
                  "certificateTemplate" => %{
                    "id" => ^id,
                    "label" => "slides"
                  }
                }
              }
            }} =
             result

    result =
      auth_query_gql_by(:get, user,
        variables: %{
          "id" => 0
        }
      )

    assert {:ok,
            %{
              data: %{
                "CertificateTemplate" => %{
                  "errors" => [
                    %{"message" => "Resource not found"}
                  ]
                }
              }
            }} =
             result
  end

  @tag :cert
  test "list certificate templates", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200
        }
    end)

    _result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "slides",
            "url" => "https://docs.google.com/presentation/d/id/edit#slide=id.p",
            "description" => "lorum ipsum"
          }
        }
      )

    _result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "LMS",
            "url" => "https://docs.google.com/presentation/d/id/edit#slide=id.p",
            "description" => "lorum ipsum2"
          }
        }
      )

    result =
      auth_query_gql_by(:list, user, variables: %{})

    assert {:ok,
            %{
              data: %{
                "CertificateTemplates" => cert_templates
              }
            }} =
             result

    assert length(cert_templates) == 2

    # with a certain label
    result =
      auth_query_gql_by(:list, user, variables: %{"filter" => %{"label" => "sli"}})

    assert {:ok,
            %{
              data: %{
                "CertificateTemplates" => cert_templates
              }
            }} =
             result

    assert length(cert_templates) == 1

    # with a certain limit
    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1}})

    assert {:ok,
            %{
              data: %{
                "CertificateTemplates" => cert_templates
              }
            }} =
             result

    assert length(cert_templates) == 1

    # empty list
    result =
      auth_query_gql_by(:list, user, variables: %{"filter" => %{"label" => "new_lms"}})

    assert {:ok,
            %{
              data: %{
                "CertificateTemplates" => cert_templates
              }
            }} =
             result

    assert Enum.empty?(cert_templates)
  end

  @tag :cert
  test "count certificate templates", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200
        }
    end)

    _result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "slides",
            "url" => "https://docs.google.com/presentation/d/id/edit#slide=id.p",
            "description" => "lorum ipsum"
          }
        }
      )

    _result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "LMS",
            "url" => "https://docs.google.com/presentation/d/id/edit#slide=id.p",
            "description" => "lorum ipsum2"
          }
        }
      )

    result =
      auth_query_gql_by(:count, user, variables: %{})

    assert {:ok,
            %{
              data: %{
                "countCertificateTemplates" => 2
              }
            }} =
             result

    # with a certain label
    result =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"label" => "sli"}})

    assert {:ok,
            %{
              data: %{
                "countCertificateTemplates" => 1
              }
            }} =
             result

    # empty list
    result =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"label" => "new_lms"}})

    assert {:ok,
            %{
              data: %{
                "countCertificateTemplates" => 0
              }
            }} =
             result
  end

  @tag :cert
  test "delete certificate template", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200
        }
    end)

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "slides",
            "url" => "https://docs.google.com/presentation/d/id/edit#slide=id.p",
            "description" => "lorum ipsum"
          }
        }
      )

    assert {:ok,
            %{
              data: %{
                "CreateCertificateTemplate" => %{
                  "certificateTemplate" => %{"id" => id}
                }
              }
            }} =
             result

    result =
      auth_query_gql_by(:delete, user,
        variables: %{
          "id" => id
        }
      )

    assert {:ok,
            %{
              data: %{
                "deleteCertificateTemplate" => %{
                  "certificateTemplate" => %{
                    "id" => ^id,
                    "label" => "slides"
                  }
                }
              }
            }} =
             result

    # invalid ID
    result =
      auth_query_gql_by(:delete, user,
        variables: %{
          "id" => 0
        }
      )

    assert {:ok,
            %{
              data: %{
                "deleteCertificateTemplate" => %{
                  "errors" => [
                    %{"message" => "Resource not found"}
                  ]
                }
              }
            }} =
             result
  end
end
