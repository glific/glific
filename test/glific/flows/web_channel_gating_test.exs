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

  describe "flow_type derivation from blocks nodes (Glific.Flows.maybe_update_flow_type/2)" do
    # "Test Workflow" (seeded by SeedsDev.seed_test_flows/0) already carries a
    # send_interactive_msg action on node "33555b1e-008d-412d-a5b5-cec6d003731b" (action uuid
    # "fbe89505-8ba8-4b1a-9d6a-7e659d6b38b5") referencing an interactive template by static id.
    # Repointing that one field at a :blocks template exercises derivation without hand-building
    # a synthetic (and easily inconsistent) flow definition from scratch.
    @node_uuid "33555b1e-008d-412d-a5b5-cec6d003731b"
    @action_uuid "fbe89505-8ba8-4b1a-9d6a-7e659d6b38b5"

    @spec published_definition(Flow.t()) :: map()
    defp published_definition(flow),
      do: Repo.get_by!(FlowRevision, flow_id: flow.id, status: "published").definition

    @spec definition_pointing_at_template(map(), non_neg_integer()) :: map()
    defp definition_pointing_at_template(definition, interactive_template_id) do
      updated_nodes =
        Enum.map(definition["nodes"], fn
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

      Map.put(definition, "nodes", updated_nodes)
    end

    @spec blocks_template_fixture(non_neg_integer()) :: InteractiveTemplate.t()
    defp blocks_template_fixture(organization_id) do
      Fixtures.interactive_fixture(%{
        organization_id: organization_id,
        type: :blocks,
        interactive_content: %{
          "type" => "blocks",
          "version" => 1,
          "component" => "glific/image-panel",
          "props" => %{
            "id" => "course",
            "options" => %{
              "kind" => "list",
              "value" => [
                %{
                  "id" => "c1",
                  "image" => %{"kind" => "image", "value" => "https://example.com/1.png"},
                  "label" => %{"kind" => "text", "value" => "A"}
                }
              ]
            }
          }
        }
      })
    end

    test "saving a draft revision with a blocks node derives flow_type to :web_message", attrs do
      SeedsDev.seed_test_flows()
      {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})
      assert flow.flow_type == :message

      blocks_template = blocks_template_fixture(attrs.organization_id)

      definition =
        flow
        |> published_definition()
        |> definition_pointing_at_template(blocks_template.id)

      user = Repo.get_current_user()
      _revision = Flows.create_flow_revision(definition, user.id)

      updated_flow = Repo.get!(Flow, flow.id)
      assert updated_flow.flow_type == :web_message
    end

    test "removing the blocks node afterwards does not revert flow_type — the commitment is irreversible",
         attrs do
      SeedsDev.seed_test_flows()
      {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})

      blocks_template = blocks_template_fixture(attrs.organization_id)
      original_definition = published_definition(flow)
      blocks_definition = definition_pointing_at_template(original_definition, blocks_template.id)

      user = Repo.get_current_user()
      _revision = Flows.create_flow_revision(blocks_definition, user.id)
      flow = Repo.get!(Flow, flow.id)
      assert flow.flow_type == :web_message

      # Saving the original (non-blocks) definition again must not revert the flow.
      _revision = Flows.create_flow_revision(original_definition, user.id)

      reverted_flow = Repo.get!(Flow, flow.id)
      assert reverted_flow.flow_type == :web_message
    end

    test "a :message flow whose send_interactive_msg still points at a non-blocks template stays :message",
         attrs do
      SeedsDev.seed_test_flows()
      {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})

      user = Repo.get_current_user()
      _revision = Flows.create_flow_revision(published_definition(flow), user.id)

      unchanged_flow = Repo.get!(Flow, flow.id)
      assert unchanged_flow.flow_type == :message

      refute attrs |> Map.get(:organization_id) |> is_nil()
    end

    test "publish_flow/2 derives flow_type before validating, so a blocks node alongside a send_broadcast fails publish",
         attrs do
      SeedsDev.seed_test_flows()
      {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})

      blocks_template = blocks_template_fixture(attrs.organization_id)

      definition =
        flow
        |> published_definition()
        |> definition_pointing_at_template(blocks_template.id)

      updated_nodes =
        Enum.map(definition["nodes"], fn
          %{"uuid" => @node_uuid} = node ->
            broadcast_action = %{
              "uuid" => Ecto.UUID.generate(),
              "type" => "send_broadcast",
              "text" => "Broadcast message",
              "contacts" => []
            }

            Map.put(node, "actions", node["actions"] ++ [broadcast_action])

          node ->
            node
        end)

      definition = Map.put(definition, "nodes", updated_nodes)

      user = Repo.get_current_user()
      _revision = Flows.create_flow_revision(definition, user.id)

      flow = Repo.get!(Flow, flow.id)
      assert flow.flow_type == :web_message

      assert {:errors, errors} = Flows.publish_flow(flow, user.id)

      assert Enum.any?(
               errors,
               &String.contains?(&1.message, "send_broadcast' is not supported on a web channel")
             )
    end
  end
end
