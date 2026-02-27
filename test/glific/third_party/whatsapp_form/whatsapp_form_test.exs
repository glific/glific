defmodule Glific.ThirdParty.WhatsappForm.ApiClientTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase
  import Mock

  alias Glific.{
    Partners,
    Providers.Gupshup.WhatsappForms.ApiClient,
    Repo,
    Sheets.Sheet,
    WhatsappForms,
    WhatsappFormsRevisions
  }

  @org_id 1
  @meta_flow_id "1234567890"
  @form_json %{
    "version" => "7.2",
    "screens" => [
      %{
        "title" => "Feedback 1 of 2",
        "layout" => %{
          "type" => "SingleColumnLayout",
          "children" => []
        },
        "id" => "RECOMMEND",
        "data" => %{}
      },
      %{
        "title" => "Feedback 2 of 2",
        "terminal" => true,
        "success" => true,
        "layout" => %{
          "type" => "SingleColumnLayout",
          "children" => [
            %{
              "type" => "Form",
              "name" => "form",
              "children" => [
                %{
                  "type" => "Footer",
                  "on-click-action" => %{
                    "payload" => %{
                      "screen_1_Purchase_experience_0" => "${form.Purchase_experience}",
                      "screen_1_Delivery_and_setup_1" => "${form.Delivery_and_setup}",
                      "screen_1_Customer_service_2" => "${form.Customer_service}",
                      "screen_0_Leave_a_comment_1" => "${data.screen_0_Leave_a_comment_1}",
                      "screen_0_Choose_one_0" => "${data.screen_0_Choose_one_0}"
                    },
                    "name" => "complete"
                  },
                  "label" => "Done"
                }
              ]
            }
          ]
        },
        "id" => "RATE",
        "data" => %{
          "screen_0_Leave_a_comment_1" => %{
            "type" => "string",
            "__example__" => "Example"
          },
          "screen_0_Choose_one_0" => %{
            "type" => "string",
            "__example__" => "Example"
          }
        }
      }
    ]
  }

  load_gql(
    :create_whatsapp_form,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms/create.gql"
  )

  load_gql(
    :update_whatsapp_form,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms/update.gql"
  )

  load_gql(
    :whatsapp_form,
    GlificWeb.Schema,
    "assets/gql/whatsapp_forms/get.gql"
  )

  test "creates a whatsapp form", %{user: user} do
    sheet_url = "https://docs.google.com/spreadsheets/d/1A2B3C4D5E6F7G8H9I0J/edit#gid=0"

    valid_attrs = %{
      "name" => "Test Form",
      "description" => "A test WhatsApp form",
      "categories" => ["other"],
      "google_sheet_url" => sheet_url
    }

    Tesla.Mock.mock(fn
      %{method: :post, url: url} ->
        cond do
          String.contains?(url, "googleapis.com") && String.contains?(url, ":append") ->
            %Tesla.Env{
              status: 200,
              body:
                Jason.encode!(%{
                  "spreadsheetId" => "1A2B3C4D5E6F7G8H9I0J",
                  "updates" => %{
                    "spreadsheetId" => "1A2B3C4D5E6F7G8H9I0J",
                    "updatedRange" => "A1:A1",
                    "updatedRows" => 1,
                    "updatedColumns" => 1,
                    "updatedCells" => 1
                  }
                })
            }

          String.contains?(url, "/flows") ->
            %Tesla.Env{
              status: 201,
              body: %{id: "1519604592614438", status: "success", validation_errors: []}
            }

          String.contains?(url, "subscription") ->
            %Tesla.Env{
              status: 200,
              body: "{\"status\":\"success\",\"subscription\":{\"active\":true}}"
            }
        end
    end)

    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
      end
    ) do
      sheet_attrs = %{
        shortcode: "google_sheets",
        secrets: %{
          "service_account" =>
            Jason.encode!(%{
              project_id: "DEFAULT PROJECT ID",
              private_key_id: "DEFAULT API KEY",
              client_email: "DEFAULT CLIENT EMAIL",
              private_key: "DEFAULT PRIVATE KEY"
            })
        },
        is_active: true,
        organization_id: user.organization_id
      }

      Partners.create_credential(sheet_attrs)

      result =
        auth_query_gql_by(:create_whatsapp_form, user,
          variables: %{
            "input" => valid_attrs
          }
        )

      assert {:ok, query_data} = result

      assert "Test Form" = query_data.data["createWhatsappForm"]["whatsappForm"]["name"]
      assert nil != query_data.data["createWhatsappForm"]["whatsappForm"]["sheetId"]
    end
  end

  test "if sheet url is already associated with another form, create and update should fail", %{
    user: user
  } do
    sheet_url = "https://docs.google.com/spreadsheets/d/1A2B3C4D5E6F7G8H9I0J/edit#gid=0"

    valid_attrs = %{
      "name" => "Test Form",
      "description" => "A test WhatsApp form",
      "categories" => ["other"],
      "google_sheet_url" => sheet_url
    }

    Tesla.Mock.mock(fn
      %{method: :post, url: url} ->
        cond do
          String.contains?(url, "googleapis.com") && String.contains?(url, ":append") ->
            %Tesla.Env{
              status: 200,
              body:
                Jason.encode!(%{
                  "spreadsheetId" => "1A2B3C4D5E6F7G8H9I0J",
                  "updates" => %{
                    "spreadsheetId" => "1A2B3C4D5E6F7G8H9I0J",
                    "updatedRange" => "A1:A1",
                    "updatedRows" => 1,
                    "updatedColumns" => 1,
                    "updatedCells" => 1
                  }
                })
            }

          String.contains?(url, "googleapis.com") && String.contains?(url, ":append") ->
            %Tesla.Env{
              status: 200,
              body:
                Jason.encode!(%{
                  "spreadsheetId" => "1A2B3C4D5E6F7G8H9I0J",
                  "updates" => %{
                    "spreadsheetId" => "1A2B3C4D5E6F7G8H9I0J",
                    "updatedRange" => "A1:A1",
                    "updatedRows" => 1,
                    "updatedColumns" => 1,
                    "updatedCells" => 1
                  }
                })
            }

          String.contains?(url, "/flows") ->
            %Tesla.Env{
              status: 201,
              body: %{id: "1519604592614438", status: "success", validation_errors: []}
            }

          String.contains?(url, "subscription") ->
            %Tesla.Env{
              status: 200,
              body: "{\"status\":\"success\",\"subscription\":{\"active\":true}}"
            }
        end
    end)

    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
      end
    ) do
      sheet_attrs = %{
        shortcode: "google_sheets",
        secrets: %{
          "service_account" =>
            Jason.encode!(%{
              project_id: "DEFAULT PROJECT ID",
              private_key_id: "DEFAULT API KEY",
              client_email: "DEFAULT CLIENT EMAIL",
              private_key: "DEFAULT PRIVATE KEY"
            })
        },
        is_active: true,
        organization_id: user.organization_id
      }

      Partners.create_credential(sheet_attrs)

      {:ok, _result} =
        auth_query_gql_by(:create_whatsapp_form, user,
          variables: %{
            "input" => valid_attrs
          }
        )

      attrs_2 = %{
        "name" => "Test Form 2",
        "description" => "A test WhatsApp form",
        "categories" => ["other"],
        "google_sheet_url" => sheet_url
      }

      {:ok, result_2} =
        auth_query_gql_by(:create_whatsapp_form, user,
          variables: %{
            "input" => attrs_2
          }
        )

      assert "Url: has already been taken" ==
               Enum.at(result_2.data["createWhatsappForm"]["errors"], 0)["message"]
    end
  end

  test "updates a whatsapp form", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :post, url: url} ->
        cond do
          String.contains?(url, "/flows") ->
            %Tesla.Env{
              status: 201,
              body: %{id: "1519604592614438", status: "success", validation_errors: []}
            }

          String.contains?(url, "subscription") ->
            %Tesla.Env{
              status: 200,
              body: "{\"status\":\"success\",\"subscription\":{\"active\":true}}"
            }
        end
    end)

    {:ok, %{whatsapp_form: whatsapp_form}} =
      WhatsappForms.create_whatsapp_form(
        %{
          name: "Initial Form",
          description: "Initial description",
          categories: ["other"],
          organization_id: user.organization_id
        },
        user
      )

    valid_update_attrs = %{
      "name" => "Updated Test Form",
      "description" => "An updated test WhatsApp form",
      "categories" => ["other"]
    }

    Tesla.Mock.mock(fn
      %{method: :put} ->
        %Tesla.Env{
          status: 200,
          body: %{status: "success", success: true}
        }
    end)

    result =
      auth_query_gql_by(:update_whatsapp_form, user,
        variables: %{
          "updateWhatsappFormId" => whatsapp_form.id,
          "input" => valid_update_attrs
        }
      )

    assert {:ok, query_data} = result
    assert "Updated Test Form" = query_data.data["updateWhatsappForm"]["whatsappForm"]["name"]
  end

  test "updating a whatsapp form's URL should modify the corresponding sheet record", %{
    user: user
  } do
    Tesla.Mock.mock(fn
      %{method: :post, url: url} ->
        cond do
          String.contains?(url, "/flows") ->
            %Tesla.Env{
              status: 201,
              body: %{id: "1519604592614438", status: "success", validation_errors: []}
            }

          String.contains?(url, "googleapis.com") && String.contains?(url, ":append") ->
            %Tesla.Env{
              status: 200,
              body:
                Jason.encode!(%{
                  "spreadsheetId" => "1A2B3C4D5E6F7G8H9I0J",
                  "updates" => %{
                    "spreadsheetId" => "1A2B3C4D5E6F7G8H9I0J",
                    "updatedRange" => "A1:A1",
                    "updatedRows" => 1,
                    "updatedColumns" => 1,
                    "updatedCells" => 1
                  }
                })
            }

          String.contains?(url, "subscription") ->
            %Tesla.Env{
              status: 200,
              body: "{\"status\":\"success\",\"subscription\":{\"active\":true}}"
            }
        end

      %{method: :put} ->
        %Tesla.Env{
          status: 200,
          body: %{status: "success", success: true}
        }
    end)

    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
      end
    ) do
      sheet_attrs = %{
        shortcode: "google_sheets",
        secrets: %{
          "service_account" =>
            Jason.encode!(%{
              project_id: "DEFAULT PROJECT ID",
              private_key_id: "DEFAULT API KEY",
              client_email: "DEFAULT CLIENT EMAIL",
              private_key: "DEFAULT PRIVATE KEY"
            })
        },
        is_active: true,
        organization_id: user.organization_id
      }

      Partners.create_credential(sheet_attrs)

      {:ok, %{whatsapp_form: whatsapp_form}} =
        WhatsappForms.create_whatsapp_form(
          %{
            name: "Initial Form",
            description: "Initial description",
            categories: ["other"],
            organization_id: user.organization_id,
            google_sheet_url: "https://docs.google.com/spreadsheets/d/OLD/edit#gid=0"
          },
          user
        )

      {:ok, sheet_before_update} =
        Repo.fetch_by(Sheet, %{
          id: whatsapp_form.sheet_id
        })

      sheet_url = "https://docs.google.com/spreadsheets/d/NEW"

      update_attrs = %{
        "name" => "Updated Test Form",
        "description" => "An updated test WhatsApp form",
        "categories" => ["other"],
        "google_sheet_url" => sheet_url
      }

      result =
        auth_query_gql_by(:update_whatsapp_form, user,
          variables: %{
            "updateWhatsappFormId" => whatsapp_form.id,
            "input" => update_attrs
          }
        )

      assert {:ok, _query_data} = result

      {:ok, sheet_after_update} =
        Repo.fetch_by(Sheet, %{
          id: whatsapp_form.sheet_id
        })

      assert sheet_before_update.url != sheet_after_update.url
      assert sheet_after_update.url == sheet_url
    end
  end

  test "get whatsapp form", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :post, url: url} ->
        cond do
          String.contains?(url, "/flows") ->
            %Tesla.Env{
              status: 201,
              body: %{id: "1519604592614438", status: "success", validation_errors: []}
            }

          String.contains?(url, "subscription") ->
            %Tesla.Env{
              status: 200,
              body: "{\"status\":\"success\",\"subscription\":{\"active\":true}}"
            }
        end
    end)

    {:ok, %{whatsapp_form: whatsapp_form}} =
      WhatsappForms.create_whatsapp_form(
        %{
          name: "Initial Form",
          description: "Initial description",
          categories: ["other"],
          organization_id: user.organization_id
        },
        user
      )

    result =
      auth_query_gql_by(:whatsapp_form, user,
        variables: %{
          "whatsappFormId" => whatsapp_form.id
        }
      )

    assert {:ok, query_data} = result
    assert "Initial Form" = query_data.data["whatsappForm"]["whatsappForm"]["name"]
  end

  test "returns error when WhatsApp Form assets fetch fails during sync" do
    Tesla.Mock.mock(fn
      %{method: :get} = _env ->
        %Tesla.Env{
          status: 401,
          body: %{
            status: "error",
            message: "error while fetching assets"
          }
        }
    end)

    {:error, reason} = ApiClient.get_whatsapp_form_assets(@meta_flow_id, @org_id)
    assert reason.message == "error while fetching assets"
  end

  test "syncing WhatsApp Forms fails when asset download from Business Manager is unsuccessful" do
    Tesla.Mock.mock(fn
      %{method: :get} = _env ->
        %Tesla.Env{
          status: 401,
          body: %{
            status: "error",
            message: "resource not found"
          }
        }
    end)

    {:error, reason} = ApiClient.download("https://example.com/fake_download.json")
    assert reason.message == "resource not found"
  end

  test "successfully publishes WhatsApp form" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            status: "success",
            body: %{
              meta_flow_id: "1234567890"
            }
          }
        }
    end)

    assert {:ok, response} = ApiClient.publish_whatsapp_form(@meta_flow_id, @org_id)
    assert response.status == "success"
    assert response.body.meta_flow_id == @meta_flow_id
  end

  test "fails to publish WhatsApp form due to invalid request" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 400,
          body: %{error: "Invalid flow ID"}
        }
    end)

    assert {:error, body} = ApiClient.publish_whatsapp_form(@meta_flow_id, @org_id)
    assert body.error == "Invalid flow ID"
  end

  test "handles server error response" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 500,
          body: %{error: "Internal server error"}
        }
    end)

    assert {:error, body} = ApiClient.publish_whatsapp_form(@meta_flow_id, @org_id)
    assert body.error == "Internal server error"
  end

  test "handles network error gracefully" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        {:error, %Tesla.Error{reason: :timeout}}
    end)

    assert {:error, "%Tesla.Error{env: nil, stack: [], reason: :timeout}"} =
             ApiClient.publish_whatsapp_form(@meta_flow_id, @org_id)
  end

  test "handles unexpected HTTP status codes" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 403,
          body: %{error: "Unauthorized request"}
        }
    end)

    assert {:error, body} = ApiClient.publish_whatsapp_form(@meta_flow_id, @org_id)
    assert body.error == "Unauthorized request"
  end

  test "creates whatsapp form and handles duplicate tag error gracefully", %{user: user} do
    valid_attrs = %{
      name: "Test Form",
      description: "A test WhatsApp form",
      categories: ["other"],
      organization_id: user.organization_id
    }

    Tesla.Mock.mock(fn
      %{method: :post, url: url} ->
        cond do
          String.contains?(url, "/flows") ->
            %Tesla.Env{
              status: 201,
              body: %{id: "form123", status: "success", validation_errors: []}
            }

          String.contains?(url, "/subscription") ->
            %Tesla.Env{status: 400, body: "Duplicate component tag"}
        end
    end)

    result = WhatsappForms.create_whatsapp_form(valid_attrs, user)
    # Should still succeed and create the form
    assert {:ok, %{whatsapp_form: whatsapp_form}} = result
    assert whatsapp_form.name == "Test Form"
  end

  test "does not create whatsapp form if subscription API fails with other error", %{user: user} do
    valid_attrs = %{
      name: "Test Form",
      description: "A test WhatsApp form",
      categories: ["other"],
      organization_id: user.organization_id
    }

    Tesla.Mock.mock(fn
      %{method: :post, url: url} ->
        cond do
          String.contains?(url, "/flows") ->
            %Tesla.Env{
              status: 201,
              body: %{id: "form123", status: "success", validation_errors: []}
            }

          String.contains?(url, "/subscription") ->
            %Tesla.Env{status: 500, body: "Internal server error"}
        end
    end)

    result = WhatsappForms.create_whatsapp_form(valid_attrs, user)
    assert {:error, %Tesla.Env{status: 500, body: "Internal server error"}} = result
  end

  test "should create the second form without calling subscription api", %{user: user} do
    valid_attrs1 = %{
      name: "Test Form",
      description: "A test WhatsApp form",
      categories: ["other"],
      organization_id: user.organization_id
    }

    valid_attrs2 = %{
      name: "Test Form 2",
      description: "Another test WhatsApp form",
      categories: ["other"],
      organization_id: user.organization_id
    }

    Tesla.Mock.mock(fn
      %{method: :post, url: url} ->
        cond do
          String.contains?(url, "/flows") ->
            %Tesla.Env{
              status: 201,
              body: %{id: "form123", status: "success", validation_errors: []}
            }

          String.contains?(url, "subscription") ->
            %Tesla.Env{
              status: 200,
              body: "{\"status\":\"success\",\"subscription\":{\"active\":true}}"
            }
        end
    end)

    result = WhatsappForms.create_whatsapp_form(valid_attrs1, user)
    assert {:ok, %{whatsapp_form: whatsapp_form}} = result
    assert whatsapp_form.name == "Test Form"

    result2 = WhatsappForms.create_whatsapp_form(valid_attrs2, user)
    # Should still succeed and create the form
    assert {:ok, %{whatsapp_form: whatsapp_form2}} = result2
    assert whatsapp_form2.name == "Test Form 2"
  end

  test "returns correct headers extracted from real form structure", %{
    organization_id: organization_id,
    user: user
  } do
    Tesla.Mock.mock(fn
      %{method: :post, url: url} ->
        cond do
          String.contains?(url, "googleapis.com") && String.contains?(url, ":append") ->
            %Tesla.Env{
              status: 200,
              body:
                Jason.encode!(%{
                  "spreadsheetId" => "test_id",
                  "updates" => %{
                    "updatedRange" => "A1:Z1",
                    "updatedRows" => 1
                  }
                })
            }

          String.contains?(url, "/flows") ->
            %Tesla.Env{
              status: 201,
              body: %{id: "1519604592614438", status: "success", validation_errors: []}
            }

          String.contains?(url, "subscription") ->
            %Tesla.Env{
              status: 200,
              body: "{\"status\":\"success\",\"subscription\":{\"active\":true}}"
            }
        end
    end)

    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
      end
    ) do
      valid_attrs = %{
        shortcode: "google_sheets",
        secrets: %{
          "service_account" =>
            Jason.encode!(%{
              project_id: "DEFAULT PROJECT ID",
              private_key_id: "DEFAULT API KEY",
              client_email: "DEFAULT CLIENT EMAIL",
              private_key: "DEFAULT PRIVATE KEY"
            })
        },
        is_active: true,
        organization_id: organization_id
      }

      Partners.create_credential(valid_attrs)

      # Create a form with the complete structure from @form_json
      {:ok, %{whatsapp_form: whatsapp_form}} =
        WhatsappForms.create_whatsapp_form(
          %{
            name: "Test Form with Headers",
            description: "A test WhatsApp form with headers",
            categories: ["other"],
            organization_id: organization_id,
            google_sheet_url: "https://docs.google.com/spreadsheets/d/test_id/edit#gid=0"
          },
          user
        )

      WhatsappFormsRevisions.save_revision(
        %{
          whatsapp_form_id: whatsapp_form.id,
          definition: @form_json
        },
        user
      )

      {:ok, whatsapp_form} =
        whatsapp_form.id
        |> WhatsappForms.get_whatsapp_form_by_id()

      assert {:ok, headers} = WhatsappForms.append_headers_to_sheet(whatsapp_form)

      assert length(headers) == 9

      # Verify default headers are present
      assert "timestamp" in headers
      assert "contact_phone_number" in headers
      assert "whatsapp_form_id" in headers
      assert "whatsapp_form_name" in headers

      # Verify form fields extracted from form_json payload are present
      assert "screen_1_Purchase_experience_0" in headers
      assert "screen_1_Delivery_and_setup_1" in headers
      assert "screen_1_Customer_service_2" in headers
      assert "screen_0_Leave_a_comment_1" in headers
      assert "screen_0_Choose_one_0" in headers
    end
  end
end
