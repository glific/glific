defmodule Glific.AI.ToolDetailsTest do
  @moduledoc """
  The detail each tool returns when asked for more than its summary.

  `Glific.AI.ToolsTest` proves the gateway's guarantees and that every tool
  answers; these assert what comes back once there is data to find.
  """

  use Glific.DataCase

  alias Glific.{
    AI.Tools,
    AIEvaluations.AIEvaluation,
    Contacts.ContactHistory,
    Fixtures,
    Flows.FlowResult,
    Flows.FlowRevision,
    Flows.WebhookLog,
    Groups,
    Repo,
    Tags
  }

  setup do
    user = Fixtures.user_fixture(%{organization_id: 1})
    contact = Fixtures.contact_fixture(%{organization_id: 1})
    flow = Fixtures.flow_fixture(%{organization_id: 1, name: "Registration flow"})

    %{user: user, contact: contact, flow: flow}
  end

  describe "templates" do
    test "a session template returns exactly the documented fields", %{user: user} do
      template = Fixtures.session_template_fixture(%{organization_id: 1})

      assert {:ok, templates} = Tools.run("list_templates", %{}, user)
      found = Enum.find(templates, &(&1.id == template.id))

      assert Map.keys(found) |> Enum.sort() ==
               Enum.sort([
                 :id,
                 :label,
                 :shortcode,
                 :body,
                 :is_hsm,
                 :status,
                 :category,
                 :is_active,
                 :language_id
               ])

      assert found.label == template.label
      assert found.body == template.body
      assert found.is_hsm == template.is_hsm
    end

    test "interactive templates are a different kind, not a different tool", %{user: user} do
      assert {:ok, interactive} = Tools.run("list_templates", %{"kind" => "interactive"}, user)
      assert is_list(interactive)

      for one <- interactive, do: assert(Map.has_key?(one, :interactive_content))
    end

    test "a session-only filter is refused on the interactive kind", %{user: user} do
      assert {:error, message} =
               Tools.run(
                 "list_templates",
                 %{"kind" => "interactive", "status" => "APPROVED"},
                 user
               )

      assert message =~ "apply only to session templates"
    end
  end

  describe "triggers" do
    test "a trigger returns exactly the documented fields", %{user: user, flow: flow} do
      trigger = Fixtures.trigger_fixture(%{organization_id: 1, flow_id: flow.id})

      assert {:ok, triggers} = Tools.run("list_triggers", %{}, user)
      found = Enum.find(triggers, &(&1.id == trigger.id))

      assert Map.keys(found) |> Enum.sort() ==
               Enum.sort([
                 :id,
                 :name,
                 :flow_id,
                 :is_active,
                 :is_repeating,
                 :frequency,
                 :start_at,
                 :next_trigger_at,
                 :last_trigger_at
               ])

      assert found.flow_id == trigger.flow_id
      assert found.name == trigger.name
      assert found.is_active == trigger.is_active
    end

    test "the limit is clamped", %{user: user, flow: flow} do
      Fixtures.trigger_fixture(%{organization_id: 1, flow_id: flow.id})

      assert {:ok, one} = Tools.run("list_triggers", %{"limit" => 1}, user)
      assert length(one) <= 1
    end
  end

  describe "assistants" do
    test "an assistant's active configuration explains how it answers", %{user: user} do
      assistant = Fixtures.assistant_fixture(%{organization_id: 1})

      version =
        Fixtures.assistant_config_version_fixture(%{
          organization_id: 1,
          assistant_id: assistant.id
        })

      assistant =
        assistant
        |> Ecto.Changeset.change(%{active_config_version_id: version.id})
        |> Repo.update!()

      assert {:ok, bare} = Tools.run("get_assistant", %{"assistant_id" => assistant.id}, user)
      refute Map.has_key?(bare, :config)

      assert {:ok, described} =
               Tools.run(
                 "get_assistant",
                 %{"assistant_id" => assistant.id, "include" => ["config"]},
                 user
               )

      assert described.config.prompt == version.prompt
      assert described.config.model == version.model
    end

    test "an assistant with no configuration is described, not refused", %{user: user} do
      assistant = Fixtures.assistant_fixture(%{organization_id: 1})

      assert {:ok, described} =
               Tools.run(
                 "get_assistant",
                 %{"assistant_id" => assistant.id, "include" => ["config"]},
                 user
               )

      refute described.config
    end

    test "an evaluation returns exactly the documented fields", %{user: user} do
      assistant = Fixtures.assistant_fixture(%{organization_id: 1})

      version =
        Fixtures.assistant_config_version_fixture(%{
          organization_id: 1,
          assistant_id: assistant.id
        })

      golden_qa = Fixtures.golden_qa_fixture(%{organization_id: 1})

      {:ok, evaluation} =
        %AIEvaluation{}
        |> AIEvaluation.changeset(%{
          name: "nightly run",
          organization_id: 1,
          assistant_config_version_id: version.id,
          golden_qa_id: golden_qa.id,
          status: :completed
        })
        |> Repo.insert()

      assert {:ok, evaluations} = Tools.run("list_evaluations", %{}, user)
      found = Enum.find(evaluations, &(&1.id == evaluation.id))

      # The hand-written mapping is the tool's contract; a schema field added or
      # renamed should fail here rather than silently vanish from the answer.
      assert Map.keys(found) |> Enum.sort() ==
               Enum.sort([
                 :id,
                 :name,
                 :status,
                 :failure_reason,
                 :results,
                 :golden_qa_id,
                 :assistant_config_version_id,
                 :inserted_at
               ])

      assert found.name == "nightly run"
      assert found.status == :completed
      assert found.assistant_config_version_id == version.id
    end

    test "an assistant returns exactly the documented fields", %{user: user} do
      assistant = Fixtures.assistant_fixture(%{organization_id: 1})

      assert {:ok, assistants} = Tools.run("list_assistants", %{}, user)
      found = Enum.find(assistants, &(&1.id == assistant.id))

      assert Map.keys(found) |> Enum.sort() ==
               Enum.sort([
                 :id,
                 :name,
                 :description,
                 :assistant_display_id,
                 :clone_status,
                 :active_config_version_id,
                 :inserted_at
               ])

      assert found.name == assistant.name
    end

    test "evaluations can bring their golden datasets along", %{user: user} do
      assert {:ok, bare} = Tools.run("list_evaluations", %{}, user)
      assert is_list(bare)

      assert {:ok, %{evaluations: _, datasets: datasets}} =
               Tools.run("list_evaluations", %{"include" => ["datasets"]}, user)

      assert is_list(datasets)
    end
  end

  describe "contacts" do
    test "each include adds only what was asked for", %{user: user, contact: contact} do
      {:ok, _} =
        %ContactHistory{}
        |> ContactHistory.changeset(%{
          contact_id: contact.id,
          organization_id: 1,
          event_type: "contact_fields_updated",
          event_label: "Age set to 30",
          event_datetime: DateTime.utc_now()
        })
        |> Repo.insert()

      assert {:ok, bare} = Tools.run("get_contact", %{"contact_id" => contact.id}, user)

      for extra <- [:history, :messages, :profiles, :tickets, :certificates],
          do: refute(Map.has_key?(bare, extra))

      assert {:ok, all} =
               Tools.run(
                 "get_contact",
                 %{
                   "contact_id" => contact.id,
                   "include" => ["history", "messages", "profiles", "tickets", "certificates"]
                 },
                 user
               )

      assert [%{event_label: "Age set to 30"} | _] = all.history
      assert is_list(all.messages)
      assert is_list(all.profiles)
      assert is_list(all.tickets)
      assert is_list(all.certificates)
    end

    test "a collection filter returns only that collection's contacts", %{
      user: user,
      contact: contact
    } do
      group = Fixtures.group_fixture(%{organization_id: 1})
      outsider = Fixtures.contact_fixture(%{organization_id: 1, phone: "919000000111"})

      {:ok, _} =
        Groups.create_contact_group(%{
          contact_id: contact.id,
          group_id: group.id,
          organization_id: 1
        })

      assert {:ok, in_collection} =
               Tools.run("list_contacts", %{"collection_id" => group.id}, user)

      ids = Enum.map(in_collection, & &1.id)
      assert contact.id in ids
      refute outsider.id in ids
    end

    test "a tag filter returns only the tagged contacts", %{user: user, contact: contact} do
      tag = Fixtures.tag_fixture(%{organization_id: 1})
      outsider = Fixtures.contact_fixture(%{organization_id: 1, phone: "919000000222"})

      {:ok, _} =
        Tags.create_contact_tag(%{
          contact_id: contact.id,
          tag_id: tag.id,
          organization_id: 1
        })

      assert {:ok, tagged} = Tools.run("list_contacts", %{"tag_id" => tag.id}, user)

      ids = Enum.map(tagged, & &1.id)
      assert contact.id in ids
      refute outsider.id in ids
    end
  end

  describe "flows" do
    test "every include brings its own detail", %{user: user, flow: flow, contact: contact} do
      context = Fixtures.flow_context_fixture(%{flow_id: flow.id, organization_id: 1})
      # Inserted directly so the log belongs to this flow.
      {:ok, _} =
        WebhookLog.create_webhook_log(%{
          url: "https://example.org/hook",
          method: "POST",
          status_code: 500,
          error: "upstream said no",
          flow_id: flow.id,
          contact_id: contact.id,
          organization_id: 1
        })

      {:ok, _} =
        %FlowResult{}
        |> FlowResult.changeset(%{
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          organization_id: 1,
          contact_id: Fixtures.contact_fixture(%{organization_id: 1}).id,
          flow_version: 1,
          flow_context_id: context.id,
          results: %{"age" => %{"input" => "30"}}
        })
        |> Repo.insert()

      FlowRevision
      |> Ecto.Query.where([r], r.flow_id == ^flow.id)
      |> Repo.update_all(
        set: [
          status: "draft",
          definition: %{
            "nodes" => [
              %{
                "uuid" => "n1",
                "actions" => [%{"type" => "send_msg", "text" => String.duplicate("long ", 60)}],
                "router" => %{"type" => "switch", "categories" => [%{"name" => "Yes"}]},
                "exits" => [%{"destination_uuid" => "n2"}]
              }
            ]
          }
        ]
      )

      assert {:ok, described} =
               Tools.run(
                 "get_flow",
                 %{
                   "flow_id" => flow.id,
                   "status" => "draft",
                   "include" => ["contacts", "counts", "results", "webhooks"]
                 },
                 user
               )

      assert [node] = described.nodes
      assert node.waits_for_reply
      assert node.router.categories == ["Yes"]
      assert [%{type: "send_msg", text: text}] = node.actions
      assert String.ends_with?(text, "…")

      assert %{waiting_at_node: _, completed: _, stopped: _} = described.contacts
      assert is_list(described.counts)
      assert [%{results: %{"age" => _}} | _] = described.results
      assert [%{url: _} | _] = described.webhooks
    end

    test "sheets can bring their synced rows", %{user: user} do
      assert {:ok, bare} = Tools.run("list_sheets", %{}, user)
      assert is_list(bare)

      assert {:ok, with_rows} = Tools.run("list_sheets", %{"include" => ["rows"]}, user)
      assert is_list(with_rows)
    end
  end

  describe "the organisation" do
    test "daily volume and staff come back", %{user: user} do
      assert {:ok, stats} = Tools.run("daily_stats", %{"limit" => 5}, user)
      assert is_list(stats)

      assert {:ok, users} = Tools.run("list_users", %{}, user)
      assert Enum.any?(users, &(&1.id == user.id))
      assert Enum.all?(users, &Map.has_key?(&1, :roles))
    end
  end

  describe "group chats" do
    test "a group's messages and members are separate includes", %{user: user} do
      phone = Fixtures.wa_managed_phone_fixture(%{organization_id: 1})
      group = Fixtures.wa_group_fixture(%{organization_id: 1, wa_managed_phone_id: phone.id})

      assert {:ok, only_messages} =
               Tools.run(
                 "get_group_chat",
                 %{"wa_group_id" => group.id, "include" => ["messages"]},
                 user
               )

      assert is_list(only_messages.messages)
      refute Map.has_key?(only_messages, :members)

      assert {:ok, only_members} =
               Tools.run(
                 "get_group_chat",
                 %{"wa_group_id" => group.id, "include" => ["members"]},
                 user
               )

      assert is_list(only_members.members)
      refute Map.has_key?(only_members, :messages)
    end

    test "managed phones ride along with the groups", %{user: user} do
      assert {:ok, %{groups: groups, managed_phones: phones}} =
               Tools.run("list_group_chats", %{"include" => ["phones"]}, user)

      assert is_list(groups)
      assert is_list(phones)
    end
  end
end
