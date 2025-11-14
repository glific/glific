defmodule Glific.ThirdParty.WhatsappForm.ApiClientTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
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
    valid_attrs = %{
      "name" => "Test Form",
      "formJson" => Jason.encode!(@form_json),
      "description" => "A test WhatsApp form",
      "categories" => ["other"]
    }

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 201,
          body: %{id: "1519604592614438", status: "success", validation_errors: []}
        }
    end)

    result =
      auth_query_gql_by(:create_whatsapp_form, user,
        variables: %{
          "input" => valid_attrs
        }
      )

    assert {:ok, query_data} = result
    assert "Test Form" = query_data.data["createWhatsappForm"]["whatsappForm"]["name"]
  end

  test "updates a whatsapp form", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 201,
          body: %{id: "1519604592614438", status: "success", validation_errors: []}
        }
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
      %{method: :post} ->
        %Tesla.Env{
          status: 201,
          body: %{id: "1519604592614438", status: "success", validation_errors: []}
        }
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
end
