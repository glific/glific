defmodule Glific.ThirdParty.WhatsappForm.ApiClientTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Providers.Gupshup.WhatsappForms.ApiClient
  }

  @flow_id "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
  @org_id 1

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

    assert {:ok, response} = ApiClient.publish_wa_form(@flow_id, @org_id)
    assert response.status == "success"
    assert response.body.meta_flow_id == @flow_id
  end

  test "fails to publish WhatsApp form due to invalid request" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 400,
          body: %{error: "Invalid flow ID"}
        }
    end)

    assert {:error, body} = ApiClient.publish_wa_form(@flow_id, @org_id)
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

    assert {:error, body} = ApiClient.publish_wa_form(@flow_id, @org_id)
    assert body.error == "Internal server error"
  end

  test "handles network error gracefully" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        {:error, %Tesla.Error{reason: :timeout}}
    end)

    assert {:error, "%Tesla.Error{env: nil, stack: [], reason: :timeout}"} =
             ApiClient.publish_wa_form(@flow_id, @org_id)
  end

  test "handles unexpected HTTP status codes" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 403,
          body: %{error: "Unauthorized request"}
        }
    end)

    assert {:error, body} = ApiClient.publish_wa_form(@flow_id, @org_id)
    assert body.error == "Unauthorized request"
  end
end
