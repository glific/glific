defmodule Glific.ThirdParty.WhatsappForm.ApiClienTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Providers.Gupshup.WhatsappForms.ApiClient
  }

  @flow_id "flow-8f91de44-b123-482e-bb52-77f1c3a78df0"
  @org_id 1

  test "fails to publish WhatsApp form due to invalid request" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 400,
          body: %{"error" => "Invalid flow ID"}
        }
    end)

    assert {:error, body} = ApiClient.publish_wa_form(@flow_id, @org_id)
    assert body["error"] == "Invalid flow ID"
  end
end
