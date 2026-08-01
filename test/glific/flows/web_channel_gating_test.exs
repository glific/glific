defmodule Glific.Flows.WebChannelGatingTest do
  @moduledoc """
  Tests for the web-channel capability gating: a flow context whose triggering message
  arrived over the web channel may send plain text AND interactive messages
  (quick_reply/list/location_request_message), but not broadcasts or templated (HSM)
  sends. Covers both the runtime safety net (Glific.Flows.Action.execute/3) and the
  flow-validation gate (Glific.Flows.Flow.web_channel_capability_errors/2).
  """
  use Glific.DataCase

  alias Glific.{
    Contacts.Contact,
    Flows,
    Notifications,
    Repo,
    Seeds.SeedsDev
  }

  alias Glific.Flows.{Action, Flow, FlowContext}
  alias Glific.Templates.InteractiveTemplate

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_contacts()
    SeedsDev.seed_interactives(organization)
    :ok
  end

  @spec web_flow_context(map()) :: FlowContext.t()
  defp web_flow_context(attrs) do
    contact = Repo.get_by(Contact, %{name: "Default receiver"})

    {:ok, context} =
      FlowContext.create_flow_context(%{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: contact.id,
        organization_id: attrs.organization_id,
        channel: "web"
      })

    Repo.preload(context, [:flow, :contact])
  end

  @spec notification_messages(non_neg_integer()) :: [String.t()]
  defp notification_messages(organization_id) do
    %{filter: %{organization_id: organization_id}}
    |> Notifications.list_notifications()
    |> Enum.map(& &1.message)
  end

  describe "runtime gating (Action.execute/3) for web channel flow contexts" do
    test "send_interactive_msg is sent over the web channel with channel: \"web\"", attrs do
      Glific.Partners.organization(attrs.organization_id)
      context = web_flow_context(attrs)
      interactive = Repo.get_by(InteractiveTemplate, %{label: "Quick Reply Text"})

      action = %Action{
        type: "send_interactive_msg",
        interactive_template_id: interactive.id
      }

      assert {:ok, _updated_context, []} = Action.execute(action, context, [])

      message =
        Glific.Messages.Message
        |> Ecto.Query.where([m], m.contact_id == ^context.contact_id)
        |> Ecto.Query.last()
        |> Repo.one()

      assert message.channel == "web"
      assert message.type in [:quick_reply, :list, :location_request_message]

      refute Enum.any?(
               notification_messages(attrs.organization_id),
               &String.contains?(&1, "send_interactive_msg is not supported on the web channel")
             )
    end

    test "send_broadcast is blocked and a notification is created", attrs do
      context = web_flow_context(attrs)

      action = %Action{
        type: "send_broadcast",
        text: "Broadcast message on web",
        contacts: []
      }

      assert {:ok, ^context, []} = Action.execute(action, context, [])

      assert Enum.any?(
               notification_messages(attrs.organization_id),
               &String.contains?(&1, "send_broadcast is not supported on the web channel")
             )
    end

    test "a templated (HSM) send_msg is blocked and a notification is created", attrs do
      context = web_flow_context(attrs)

      action = %Action{
        type: "send_msg",
        text: "Templated message on web",
        templating: %{expression: "some expression"}
      }

      assert {:ok, ^context, []} = Action.execute(action, context, [])

      assert Enum.any?(
               notification_messages(attrs.organization_id),
               &String.contains?(&1, "template (HSM) is not supported on the web channel")
             )
    end

    test "a plain-text send_msg on the web channel is sent with channel: \"web\"", attrs do
      Glific.Partners.organization(attrs.organization_id)
      context = web_flow_context(attrs)

      action = %Action{
        type: "send_msg",
        text: "Plain text message on web"
      }

      assert {:ok, _updated_context, []} = Action.execute(action, context, [])

      message =
        Glific.Messages.Message
        |> Ecto.Query.where([m], m.contact_id == ^context.contact_id)
        |> Ecto.Query.last()
        |> Repo.one()

      assert message.body == "Plain text message on web"
      assert message.channel == "web"
    end
  end

  describe "validation-time gating (Flow.validate_flow/3) for :web_message flows" do
    test "publishing a :web_message flow flags broadcast but not interactive actions",
         attrs do
      SeedsDev.seed_test_flows()

      {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})
      {:ok, flow} = Flows.update_flow(flow, %{flow_type: :web_message})

      errors = Flow.validate_flow(flow.organization_id, "published", %{id: flow.id})

      error_messages = Enum.map(errors, &elem(&1, 1))

      assert Enum.any?(
               error_messages,
               &String.contains?(&1, "send_broadcast' is not supported on a web channel")
             )

      # interactive messages are now supported on the web channel, so they are not flagged
      refute Enum.any?(
               error_messages,
               &String.contains?(&1, "send_interactive_msg' is not supported on a web channel")
             )

      refute attrs |> Map.get(:organization_id) |> is_nil()
    end

    test "a :message (whatsapp) flow with the same actions is not flagged by the web gate" do
      SeedsDev.seed_test_flows()

      {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})

      errors = Flow.validate_flow(flow.organization_id, "published", %{id: flow.id})
      error_messages = Enum.map(errors, &elem(&1, 1))

      refute Enum.any?(error_messages, &String.contains?(&1, "not supported on a web channel"))
    end
  end
end
