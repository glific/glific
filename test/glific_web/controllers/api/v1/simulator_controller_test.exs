defmodule GlificWeb.API.V1.SimulatorControllerTest do
  @moduledoc """
  Tests for the authenticated simulator endpoint: that a simulator payload is received into
  the caller's organization, and that anything else is refused.
  """
  use GlificWeb.ConnCase

  import Ecto.Query

  alias Glific.{
    Contacts,
    Fixtures,
    Messages.Message,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    SeedsDev.seed_organizations()
    SeedsDev.seed_contacts()
    :ok
  end

  defp simulator_phone do
    Contacts.simulator_phone_prefix() <> "_1"
  end

  defp payload(phone, text) do
    %{
      "type" => "message",
      "payload" => %{
        "id" => Ecto.UUID.generate(),
        "type" => "text",
        "payload" => %{"text" => text},
        "sender" => %{"phone" => phone, "name" => "Glific Simulator One"}
      }
    }
  end

  defp last_message_body(text) do
    Message
    |> where([message], message.body == ^text)
    |> Repo.all(skip_organization_id: true)
  end

  describe "POST /api/v1/simulator/message" do
    test "accepts a simulator message and receives it into the organization", %{conn: conn} do
      text = "hello from the simulator"
      authed_conn = api_auth_conn(conn, Fixtures.user_fixture(%{roles: ["staff"]}))

      response = post(authed_conn, "/api/v1/simulator/message", payload(simulator_phone(), text))

      assert response.status == 200
      assert [message] = last_message_body(text)
      assert message.organization_id == 1
    end

    test "rejects a payload naming a contact that is not a simulator", %{conn: conn} do
      text = "forged beneficiary message"
      authed_conn = api_auth_conn(conn, Fixtures.user_fixture(%{roles: ["staff"]}))

      response = post(authed_conn, "/api/v1/simulator/message", payload("919876543211", text))

      assert json_response(response, 403)["error"]["status"] == 403
      assert [] == last_message_body(text)
    end

    test "rejects a payload with no sender", %{conn: conn} do
      authed_conn = api_auth_conn(conn, Fixtures.user_fixture(%{roles: ["staff"]}))

      response =
        post(authed_conn, "/api/v1/simulator/message", %{
          "type" => "message",
          "payload" => %{"type" => "text"}
        })

      assert json_response(response, 403)["error"]["status"] == 403
    end

    test "refuses an unauthenticated caller", %{conn: conn} do
      text = "unauthenticated simulator message"

      response = post(conn, "/api/v1/simulator/message", payload(simulator_phone(), text))

      assert json_response(response, 401)["error"]["code"] == 401
      assert [] == last_message_body(text)
    end
  end
end
