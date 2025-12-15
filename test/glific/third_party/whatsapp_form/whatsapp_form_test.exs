defmodule Glific.ThirdParty.WhatsappForm.ApiClientTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase
  import Mock

  alias Glific.{
    Partners,
    Providers.Gupshup.WhatsappForms.ApiClient,
    WhatsappForms
  }

  @org_id 1
  @meta_flow_id "1234567890"
  @form_json %{
    "version" => "7.2",
    "screens" => [
      %{
        "id" => "RECOMMEND",
        "title" => "Feedback 1 of 2",
        "data" => %{},
        "layout" => %{}
      },
      %{
        "id" => "RATE",
        "title" => "Feedback 2 of 2",
        "data" => %{},
        "terminal" => true,
        "success" => true,
        "layout" => %{}
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
      "formJson" => Jason.encode!(@form_json),
      "description" => "A test WhatsApp form",
      "categories" => ["other"],
      "google_sheet_url" => sheet_url
    }

    Tesla.Mock.mock(fn
      %{method: :get, url: url} when is_binary(url) ->
        cond do
          String.contains?(url, "docs.google.com/spreadsheets") ->
            %Tesla.Env{
              status: 200,
              body: "Key,Value\ntest1,value1\ntest2,value2"
            }

          true ->
            %Tesla.Env{status: 200}
        end

      %{method: :get, url: nil} ->
        {:error, :invalid_url}

      %{method: :post, url: url} ->
        cond do
          String.contains?(url, "googleapis.com") && String.contains?(url, ":append") ->
            %Tesla.Env{
              status: 200,
              body: Jason.encode!(%{
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
      WhatsappForms.create_whatsapp_form(%{
        name: "Initial Form",
        form_json: @form_json,
        description: "Initial description",
        categories: ["other"],
        organization_id: user.organization_id
      })

    valid_update_attrs = %{
      "name" => "Updated Test Form",
      "formJson" => Jason.encode!(@form_json),
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
      WhatsappForms.create_whatsapp_form(%{
        name: "Initial Form",
        form_json: @form_json,
        description: "Initial description",
        categories: ["other"],
        organization_id: user.organization_id
      })

    result =
      auth_query_gql_by(:whatsapp_form, user,
        variables: %{
          "whatsappFormId" => whatsapp_form.id
        }
      )

    assert {:ok, query_data} = result
    assert "Initial Form" = query_data.data["whatsappForm"]["whatsappForm"]["name"]
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
      form_json: @form_json,
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

    result = WhatsappForms.create_whatsapp_form(valid_attrs)
    # Should still succeed and create the form
    assert {:ok, %{whatsapp_form: whatsapp_form}} = result
    assert whatsapp_form.name == "Test Form"
  end

  test "does not create whatsapp form if subscription API fails with other error", %{user: user} do
    valid_attrs = %{
      name: "Test Form",
      form_json: @form_json,
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

    result = WhatsappForms.create_whatsapp_form(valid_attrs)
    assert {:error, %Tesla.Env{status: 500, body: "Internal server error"}} = result
  end

  test "should create the second form without calling subscription api", %{user: user} do
    valid_attrs1 = %{
      name: "Test Form",
      form_json: @form_json,
      description: "A test WhatsApp form",
      categories: ["other"],
      organization_id: user.organization_id
    }

    valid_attrs2 = %{
      name: "Test Form 2",
      form_json: @form_json,
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

    result = WhatsappForms.create_whatsapp_form(valid_attrs1)
    assert {:ok, %{whatsapp_form: whatsapp_form}} = result
    assert whatsapp_form.name == "Test Form"

    result2 = WhatsappForms.create_whatsapp_form(valid_attrs2)
    # Should still succeed and create the form
    assert {:ok, %{whatsapp_form: whatsapp_form2}} = result2
    assert whatsapp_form2.name == "Test Form 2"
  end
end
