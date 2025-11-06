defmodule Glific.ThirdParty.WhatsappForm.ApiClienTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Providers.Gupshup.WhatsappForms.ApiClient
  }

  @meta_flow_id "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
  @org_id 1
  @form_json %{
    version: "7.2",
    screens: [
      %{
        id: "RECOMMEND",
        title: "Feedback 1 of 2",
        data: %{},
        layout: %{},
      },
      %{
        id: "RATE",
        title: "Feedback 2 of 2",
        data: %{},
        terminal: true,
        success: true,
        layout: %{},
      },
    ],
  }

  test "successfully creates WhatsApp form" do
    form_params = %{
      name: "Test Form",
      categories: ["other"],
      description: "This is a test form",
      form_json: @form_json,
      organization_id: @org_id
    }

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 201,
          body: %{
            status: "success",
            body: %{
              id: 1,
              name: "Test Form",
              categories: ["other"],
              meta_flow_id: @meta_flow_id
            }
          }
        }
    end)

    assert {:ok, response} = ApiClient.create_whatsapp_form(form_params)
    assert response.status == "success"
    assert response.body.name == "Test Form"
    assert response.body.categories == ["other"]
  end

  test "successfully updates WhatsApp form" do
    form_id = 1
    update_params = %{
      name: "Updated Test Form",
      description: "This is an updated test form",
      categories: ["customer_support"],
      form_json: @form_json,
      organization_id: @org_id

    }

    Tesla.Mock.mock(fn
      %{method: :put} ->
        %Tesla.Env{
          status: 200,
          body: %{
            status: "success",
            body: %{
              id: form_id,
              name: "Updated Test Form",
              description: "This is an updated test form",
              categories: ["customer_support"]
            }
          }
        }
    end)

    assert {:ok, response} = ApiClient.update_whatsapp_form(form_id, update_params)
    assert response.status == "success"
    assert response.body.name == "Updated Test Form"
  end

  test "successfully publishes WhatsApp form" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            status: "success",
            body: %{
              meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
            }
          }
        }
    end)

    assert {:ok, response} = ApiClient.publish_wa_form(@meta_flow_id, @org_id)
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

    assert {:error, body} = ApiClient.publish_wa_form(@meta_flow_id, @org_id)
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

    assert {:error, body} = ApiClient.publish_wa_form(@meta_flow_id, @org_id)
    assert body.error == "Internal server error"
  end

  test "handles network error gracefully" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        {:error, %Tesla.Error{reason: :timeout}}
    end)

    assert {:error, "%Tesla.Error{env: nil, stack: [], reason: :timeout}"} =
             ApiClient.publish_wa_form(@meta_flow_id, @org_id)
  end

  test "handles unexpected HTTP status codes" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 403,
          body: %{error: "Unauthorized request"}
        }
    end)

    assert {:error, body} = ApiClient.publish_wa_form(@meta_flow_id, @org_id)
    assert body.error == "Unauthorized request"
  end
end
