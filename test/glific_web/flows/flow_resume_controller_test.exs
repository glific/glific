defmodule GlificWeb.Flows.FlowResumeControllerTest do
  use GlificWeb.ConnCase

  # alias GlificWeb.Flows.FlowResumeController
  alias Glific.Seeds.SeedsDev

  setup do
    SeedsDev.seed_organizations()
    :ok
  end

  describe "flow_resume_routes" do
    test "resuming and existing flow once receive webhook event", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      params = %{
        "callback" =>
          "https://api.glific.glific.com/webhook/flow_resume?organization_id=1&flow_id=20&contact_id=5&timestamp=1740203086735839&signature=b0bbfcc5e80830da9ce8603a2f1ee4089723544d44d748fa7fc73ca5106e6bf6",
        "contact_id" => 5,
        "endpoint" => "http://127.0.0.1:8000/api/v1/threads",
        "flow_id" => 20,
        "message" =>
          "Glific is an open-source, two-way messaging platform designed for nonprofits to scale their outreach via WhatsApp. It helps organizations automate conversations, manage contacts, and measure impact, all in one centralized tool",
        "organization_id" => organization_id,
        "signature" => "b0bbfcc5e80830da9ce8603a2f1ee4089723544d44d748fa7fc73ca5106e6bf6",
        "status" => "success",
        "thread_id" => "thread_yJxZazJ0bcXvFAF2TLIgM3VX",
        "timestamp" => 1_740_203_086_735_839
      }

      conn =
        conn
        |> post("/webhook/flow_resume", params)

      assert json_response(conn, 200) == ""
    end
  end
end
