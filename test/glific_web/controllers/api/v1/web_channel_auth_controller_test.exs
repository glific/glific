defmodule GlificWeb.API.V1.WebChannelAuthControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{Contacts.Contact, Repo}
  alias GlificWeb.WebChannel.Token

  describe "request_otp/2" do
    test "returns 200 when phone is present", %{conn: conn} do
      conn = post(conn, "/api/v1/web_channel/request-otp", %{"phone" => "919999988888"})
      response = json_response(conn, 200)
      assert response["data"]["phone"] == "919999988888"
      assert response["data"]["message"] == "OTP sent"
    end

    test "returns 422 when phone is missing", %{conn: conn} do
      conn = post(conn, "/api/v1/web_channel/request-otp", %{})
      response = json_response(conn, 422)
      assert response["error"]["message"]
    end

    test "returns 422 when phone is blank", %{conn: conn} do
      conn = post(conn, "/api/v1/web_channel/request-otp", %{"phone" => ""})
      response = json_response(conn, 422)
      assert response["error"]["message"]
    end
  end

  describe "verify_otp/2" do
    test "with correct otp returns a valid contact-scoped token and resolves the contact",
         %{conn: conn, organization_id: organization_id} do
      phone = "919999900001"

      conn =
        post(conn, "/api/v1/web_channel/verify-otp", %{"phone" => phone, "otp" => "9999"})

      response = json_response(conn, 200)
      assert token = response["data"]["token"]
      assert contact_id = response["data"]["contact_id"]
      assert response["data"]["phone"] == phone

      assert {:ok, %{contact_id: ^contact_id, org_id: ^organization_id}} =
               Token.verify_contact_token(token)

      assert {:ok, %Contact{phone: ^phone, organization_id: ^organization_id}} =
               Repo.fetch_by(Contact, %{id: contact_id, organization_id: organization_id})
    end

    test "with an existing contact resolves the same contact", %{
      conn: conn,
      organization_id: organization_id
    } do
      phone = "919999900002"

      conn1 =
        post(conn, "/api/v1/web_channel/verify-otp", %{"phone" => phone, "otp" => "9999"})

      response1 = json_response(conn1, 200)
      contact_id1 = response1["data"]["contact_id"]

      conn2 =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.assign(:organization_id, organization_id)
        |> post("/api/v1/web_channel/verify-otp", %{"phone" => phone, "otp" => "9999"})

      response2 = json_response(conn2, 200)
      assert response2["data"]["contact_id"] == contact_id1
    end

    test "with an incorrect otp returns 401", %{conn: conn} do
      conn =
        post(conn, "/api/v1/web_channel/verify-otp", %{
          "phone" => "919999900003",
          "otp" => "0000"
        })

      response = json_response(conn, 401)
      assert response["error"]["message"] == "Invalid OTP"
    end
  end
end
