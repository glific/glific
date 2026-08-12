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
    Fixtures,
    Flows,
    Flows.FlowRevision,
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

  describe "custom_ui channel-narrowing warning (Flow.validate_flow/3)" do
    # "Test Workflow" (seeded by SeedsDev.seed_test_flows/0) already carries a
    # send_interactive_msg action on node "33555b1e-008d-412d-a5b5-cec6d003731b" (action uuid
    # "fbe89505-8ba8-4b1a-9d6a-7e659d6b38b5") referencing an interactive template by static id.
    # Repointing that one field at a :custom_ui template exercises the warning without hand-
    # building a synthetic (and easily inconsistent) flow definition from scratch.
    @node_uuid "33555b1e-008d-412d-a5b5-cec6d003731b"
    @action_uuid "fbe89505-8ba8-4b1a-9d6a-7e659d6b38b5"

    @spec point_action_at_template(Flow.t(), non_neg_integer()) :: :ok
    defp point_action_at_template(flow, interactive_template_id) do
      revision = Repo.get_by!(FlowRevision, flow_id: flow.id, status: "published")

      updated_nodes =
        Enum.map(revision.definition["nodes"], fn
          %{"uuid" => @node_uuid} = node ->
            updated_actions =
              Enum.map(node["actions"], fn
                %{"uuid" => @action_uuid} = action ->
                  Map.put(action, "id", interactive_template_id)

                action ->
                  action
              end)

            Map.put(node, "actions", updated_actions)

          node ->
            node
        end)

      updated_definition = Map.put(revision.definition, "nodes", updated_nodes)

      revision
      |> Ecto.Changeset.change(definition: updated_definition)
      |> Repo.update!()

      :ok
    end

    test "a :message flow with a send_interactive_msg pointing at a custom_ui template is flagged, keyed by the node's uuid",
         attrs do
      SeedsDev.seed_test_flows()
      {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})

      custom_ui_template =
        Fixtures.interactive_fixture(%{
          organization_id: attrs.organization_id,
          type: :custom_ui,
          interactive_content: %{
            "type" => "custom_ui",
            "version" => "1",
            "component" => "glific/image_panel",
            "props" => %{
              "id" => "course",
              "options" => [
                %{"id" => "c1", "image" => "https://example.com/1.png", "label" => "A"}
              ]
            },
            "fallback" => "Pick a course"
          }
        })

      :ok = point_action_at_template(flow, custom_ui_template.id)

      errors = Flow.validate_flow(flow.organization_id, "published", %{id: flow.id})

      assert Enum.any?(errors, fn {key, message, _severity} ->
               key == @node_uuid and message =~ "web-only"
             end)
    end

    test "an already :web_message flow is not flagged (it has already made the channel commitment)",
         attrs do
      SeedsDev.seed_test_flows()
      {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})
      {:ok, flow} = Flows.update_flow(flow, %{flow_type: :web_message})

      custom_ui_template =
        Fixtures.interactive_fixture(%{
          organization_id: attrs.organization_id,
          type: :custom_ui,
          interactive_content: %{
            "type" => "custom_ui",
            "version" => "1",
            "component" => "glific/image_panel",
            "props" => %{
              "id" => "course",
              "options" => [
                %{"id" => "c1", "image" => "https://example.com/1.png", "label" => "A"}
              ]
            },
            "fallback" => "Pick a course"
          }
        })

      :ok = point_action_at_template(flow, custom_ui_template.id)

      errors = Flow.validate_flow(flow.organization_id, "published", %{id: flow.id})

      refute Enum.any?(errors, fn {_key, message, _severity} -> message =~ "web-only" end)
    end

    test "a :message flow whose send_interactive_msg still points at a non-custom_ui template is not flagged",
         attrs do
      SeedsDev.seed_test_flows()
      {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})

      refute attrs |> Map.get(:organization_id) |> is_nil()

      errors = Flow.validate_flow(flow.organization_id, "published", %{id: flow.id})

      refute Enum.any?(errors, fn {_key, message, _severity} -> message =~ "web-only" end)
    end
  end
end
