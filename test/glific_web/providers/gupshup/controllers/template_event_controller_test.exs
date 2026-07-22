defmodule GlificWeb.Providers.Gupshup.Controllers.TemplateEventControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Fixtures,
    Seeds.SeedsDev,
    Templates
  }

  @template_event_request_params %{
    "app" => "Glific App",
    "payload" => %{
      "type" => "status-update",
      "id" => "some-bsp-id",
      "status" => "approved",
      "elementName" => "order_update",
      "languageCode" => "en"
    },
    "timestamp" => 1_592_311_842_070,
    "type" => "template-event",
    "version" => 2
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    :ok
  end

  describe "status_update" do
    setup %{conn: conn} do
      bsp_id = Faker.String.base64(36)

      template =
        Fixtures.session_template_fixture(%{
          organization_id: conn.assigns[:organization_id],
          is_hsm: true,
          bsp_id: bsp_id,
          uuid: bsp_id,
          status: "PENDING",
          is_active: false
        })

      %{template: template, bsp_id: bsp_id}
    end

    test "approved status marks the template approved and active", %{
      conn: conn,
      template: template,
      bsp_id: bsp_id
    } do
      params =
        @template_event_request_params
        |> put_in(["payload", "id"], bsp_id)
        |> put_in(["payload", "status"], "approved")

      approved_conn = post(conn, "/gupshup", params)
      assert response(approved_conn, 200) == ""

      updated = Templates.get_session_template!(template.id)
      assert updated.status == "APPROVED"
      assert updated.is_active == true
    end

    test "rejected status marks the template rejected with a reason", %{
      conn: conn,
      template: template,
      bsp_id: bsp_id
    } do
      params =
        @template_event_request_params
        |> put_in(["payload", "id"], bsp_id)
        |> put_in(["payload", "status"], "rejected")
        |> put_in(["payload", "rejectedReason"], "Invalid format")

      rejected_conn = post(conn, "/gupshup", params)
      assert response(rejected_conn, 200) == ""

      updated = Templates.get_session_template!(template.id)
      assert updated.status == "REJECTED"
      assert updated.reason == "Invalid format"
    end

    test "rejecting an already approved, active template deactivates it", %{conn: conn} do
      bsp_id = Faker.String.base64(36)

      approved_template =
        Fixtures.session_template_fixture(%{
          organization_id: conn.assigns[:organization_id],
          is_hsm: true,
          bsp_id: bsp_id,
          uuid: bsp_id,
          status: "APPROVED",
          is_active: true
        })

      params =
        @template_event_request_params
        |> put_in(["payload", "id"], bsp_id)
        |> put_in(["payload", "status"], "rejected")
        |> put_in(["payload", "rejectedReason"], "Policy violation")

      rejected_conn = post(conn, "/gupshup", params)
      assert response(rejected_conn, 200) == ""

      updated = Templates.get_session_template!(approved_template.id)
      assert updated.status == "REJECTED"
      assert updated.is_active == false
    end

    test "unknown bsp_id is ignored and still returns 200", %{conn: conn} do
      params = put_in(@template_event_request_params, ["payload", "id"], "does-not-exist")

      unknown_conn = post(conn, "/gupshup", params)
      assert response(unknown_conn, 200) == ""
    end
  end
end
