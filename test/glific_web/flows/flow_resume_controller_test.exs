defmodule GlificWeb.Flows.FlowResumeControllerTest do
  use GlificWeb.ConnCase

  # alias GlificWeb.Flows.FlowResumeController
  alias Glific.{
    Fixtures,
    Messages,
    Repo,
    Seeds.SeedsDev
  }

  alias Glific.Flows.{
    Flow,
    FlowContext
  }

  @valid_attrs %{
    flow_id: 1,
    flow_uuid: Ecto.UUID.generate(),
    uuid_map: %{},
    node_uuid: Ecto.UUID.generate()
  }

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
        "thread_id" => "thread_yJxZazJ0bcXvFAsglific",
        "timestamp" => 1_740_203_086_735_839
      }

      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "help"})
      [node | _tail] = flow.nodes

      message = Messages.create_temp_message(organization_id, "1")
      wakeup_at = Timex.shift(Timex.now(), minutes: +3)

      flow_context =
        flow_context_fixture(%{
          node_uuid: node.uuid,
          is_await_result: true,
          wakeup_at: wakeup_at,
          is_background_flow: true,
          flow_uuid: flow.uuid,
          flow_id: flow.id
        })

      conn =
        conn
        |> post("/webhook/flow_resume", params)

      assert json_response(conn, 200) == ""
    end
  end

  def flow_context_fixture(attrs \\ %{}) do
    contact = Fixtures.contact_fixture()

    {:ok, flow_context} =
      attrs
      |> Map.put(:contact_id, contact.id)
      |> Map.put(:organization_id, contact.organization_id)
      |> Enum.into(@valid_attrs)
      |> FlowContext.create_flow_context()

    flow_context
    |> Repo.preload(:contact)
    |> Repo.preload(:flow)
  end
end
