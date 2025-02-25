defmodule GlificWeb.Flows.FlowResumeControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Fixtures,
    Flows,
    Flows.Flow,
    Flows.FlowRevision,
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

  @ai_response "Glific is an open-source, two-way messaging platform designed for nonprofits to scale their outreach via WhatsApp. It helps organizations automate conversations, manage contacts, and measure impact, all in one centralized tool"

  describe "flow_resume_routes" do
    test "resuming and existing flow once receive webhook event", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      setup_flow(organization_id)
      contact = Fixtures.contact_fixture()

      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "wfr"})

      signature_payload = %{
        "organization_id" => organization_id,
        "flow_id" => flow.id,
        "contact_id" => contact.id,
        "timestamp" => timestamp
      }

      signature =
        Glific.signature(
          organization_id,
          Jason.encode!(signature_payload),
          signature_payload["timestamp"]
        )

      params = %{
        "callback" =>
          "https://api.glific.glific.com/webhook/flow_resume?organization_id=1&flow_id=20&contact_id=5&timestamp=1740203086735839&signature=b0bbfcc5e80830da9ce8603a2f1ee4089723544d44d748fa7fc73ca5106e6bf6",
        "contact_id" => contact.id,
        "endpoint" => "http://127.0.0.1:8000/api/v1/threads",
        "flow_id" => flow.id,
        "message" => @ai_response,
        "organization_id" => organization_id,
        "signature" => signature,
        "status" => "success",
        "thread_id" => "thread_yJxZazJ0bcXvFAsglific",
        "timestamp" => timestamp
      }

      # starting the flow so the waiting for result node is executed and the flow is waiting for response
      Flows.start_contact_flow(flow, contact)

      conn =
        conn
        |> post("/webhook/flow_resume", params)

      assert json_response(conn, 200) == ""

      # once a response is received the flow moves to next node i.e. send the message which is @results.response.message
      [message | _messages] = Glific.Messages.list_messages(%{})

      # Checking the latest message should be same as the one received at the endpoint
      assert message.body == @ai_response
    end
  end

  def flow_context_fixture(contact, attrs \\ %{}) do
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

  def setup_flow(organization_id) do
    # creates a new flow named wait for result with only two nodes, starting with wait for result and then sending a message
    wait_for_result_flow =
      Repo.insert!(%Flow{
        name: "Wait for result",
        keywords: ["wfr"],
        version_number: "13.2.0",
        uuid: "6a0bd92c-3e6e-4cd5-84b2-d4e140175a90",
        organization_id: organization_id
      })

    definition =
      File.read!(Path.join(:code.priv_dir(:glific), "data/flows/" <> "wait_for_result.json"))
      |> Jason.decode!()

    Repo.insert!(%FlowRevision{
      definition: definition,
      flow_id: wait_for_result_flow.id,
      status: "published",
      organization_id: organization_id
    })
  end
end
