defmodule Glific.AI.ToolsTest do
  use Glific.DataCase

  alias Glific.{
    AI.Tools,
    AI.Tools.Reference,
    Fixtures,
    Flows.Flow,
    Flows.FlowRevision,
    Repo,
    WhatsappForms.WhatsappForm,
    WhatsappForms.WhatsappFormResponse
  }

  defmodule Misbehaving do
    @moduledoc false
    @behaviour Glific.AI.Tool

    @impl Glific.AI.Tool
    def specs do
      [
        %{
          name: "writing_tool",
          description: "attempts a write, to prove it cannot",
          parameters: []
        },
        %{
          name: "whoami_tool",
          description: "reports the identity the read ran as",
          parameters: []
        },
        %{
          name: "raising_tool",
          description: "raises, to prove the gateway catches it",
          parameters: []
        }
      ]
    end

    @impl Glific.AI.Tool
    def run("writing_tool", _args) do
      Glific.Flows.Flow
      |> Glific.Repo.all()
      |> hd()
      |> Ecto.Changeset.change(%{name: "written by a tool"})
      |> Glific.Repo.update()

      {:ok, :wrote}
    end

    def run("raising_tool", _args), do: raise("something went wrong deep inside")

    # The gateway restores the caller's identity on the way out, so which user a
    # read ran as can only be observed from inside the read itself.
    def run("whoami_tool", _args) do
      {:ok,
       %{
         user_id: Glific.Repo.get_current_user().id,
         organization_id: Glific.Repo.get_organization_id()
       }}
    end
  end

  # The gateway's guarantees cannot be proved with the real tools, since every one
  # of them is a well-behaved read. These attempt a write, and raise.
  defp modules, do: Tools.modules() ++ [Misbehaving]

  setup do
    user = Fixtures.user_fixture(%{organization_id: 1})
    flow = Fixtures.flow_fixture(%{organization_id: 1, name: "Registration flow"})
    contact = Fixtures.contact_fixture(%{organization_id: 1})

    phone = Fixtures.wa_managed_phone_fixture(%{organization_id: 1})

    wa_group =
      Fixtures.wa_group_fixture(%{organization_id: 1, wa_managed_phone_id: phone.id})

    assistant = Fixtures.assistant_fixture(%{organization_id: 1})

    %{
      user: user,
      flow: flow,
      contact: contact,
      assistant: assistant,
      wa_group: wa_group
    }
  end

  describe "the gateway's guarantees" do
    test "an unknown tool is reported, not raised", %{user: user} do
      assert {:error, message} = Tools.run("no_such_tool", %{}, user)
      assert message == ~s(There is no tool called "no_such_tool".)
    end

    test "invalid arguments are reported, not raised", %{user: user} do
      assert {:error, message} =
               Tools.run("get_flow", %{"flow_id" => "not a number"}, user)

      assert message =~ "invalid value for :flow_id option"
      assert {:error, missing} = Tools.run("get_flow", %{}, user)
      assert missing =~ "required :flow_id option not found"
    end

    test "a misspelt argument is reported, not silently dropped", %{user: user} do
      assert {:error, message} =
               Tools.run("get_contact", %{"inclde" => ["history"]}, user)

      assert message =~ ~s(get_contact has no argument "inclde")
      assert message =~ "Valid arguments:"
      assert message =~ "include"
    end

    test "an argument name that is not a known atom does not grow the atom table", %{
      user: user
    } do
      # The name is refused without being added to the atom table, which is never
      # garbage collected.
      assert {:error, _} =
               Tools.run("list_flows", %{"definitely_not_an_argument_name" => 1}, user)

      assert_raise ArgumentError, fn ->
        String.to_existing_atom("definitely_not_an_argument_name")
      end
    end

    test "an exception inside a tool comes back as a result", %{user: user} do
      assert {:error, message} = Tools.run("raising_tool", %{}, user, modules())
      assert message =~ "something went wrong deep inside"
    end

    test "a write inside a tool is refused by the database", %{user: user} do
      original = Flow |> Repo.all() |> hd()

      assert {:error, message} = Tools.run("writing_tool", %{}, user, modules())
      assert message =~ "cannot execute UPDATE in a read-only transaction"
      assert Repo.get(Flow, original.id).name == original.name
    end

    test "the caller keeps its own identity after a lookup", %{user: user} do
      before_user = Repo.get_current_user()
      before_org = Repo.get_organization_id()
      refute before_user.id == user.id

      assert {:ok, _} = Tools.run("list_flows", %{}, user)

      assert Repo.get_current_user().id == before_user.id
      assert Repo.get_organization_id() == before_org
    end

    test "the caller keeps its identity even when a tool raises", %{user: user} do
      before_user = Repo.get_current_user()

      assert {:error, _} = Tools.run("raising_tool", %{}, user, modules())
      assert Repo.get_current_user().id == before_user.id
    end

    test "the read runs as the given user, whatever the process state said", %{
      user: user
    } do
      Repo.put_current_user(Fixtures.user_fixture(%{organization_id: 1, phone: "919876500011"}))

      assert {:ok, ran_as} = Tools.run("whoami_tool", %{}, user, modules())
      assert ran_as.user_id == user.id
      assert ran_as.organization_id == user.organization_id
    end

    test "a tool cannot see another organisation's data", %{user: user} do
      other_org = Fixtures.organization_fixture(%{shortcode: "ai_tools_other"})
      other_user = Fixtures.user_fixture(%{organization_id: other_org.id, phone: "919876500012"})

      assert {:ok, mine} = Tools.run("list_flows", %{}, user)
      assert Enum.any?(mine, &(&1.name == "Registration flow"))

      assert {:ok, theirs} = Tools.run("list_flows", %{}, other_user)
      refute Enum.any?(theirs, &(&1.name == "Registration flow"))
    end

    test "every operation declares a name, a description and a schema" do
      names = Enum.map(Tools.all(), & &1.name)
      assert names == Enum.uniq(names)

      for spec <- Tools.all() do
        assert is_binary(spec.name) and spec.name != ""
        assert is_binary(spec.description) and spec.description != ""
        assert is_list(spec.parameters)
        assert {:ok, {module, ^spec}} = Tools.fetch(spec.name)
        assert function_exported?(module, :run, 2)
      end
    end
  end

  describe "flows" do
    test "list_flows finds a flow by partial name", %{user: user} do
      assert {:ok, flows} = Tools.run("list_flows", %{"name" => "Registration"}, user)
      assert [%{name: "Registration flow"} | _] = flows
    end

    test "get_flow describes the nodes of a revision that exists", %{
      user: user,
      flow: flow
    } do
      assert {:ok, described} =
               Tools.run(
                 "get_flow",
                 %{"flow_id" => flow.id, "status" => "draft"},
                 user,
                 modules()
               )

      assert described.name == "Registration flow"
      assert described.revision == "draft"
      assert is_list(described.nodes)
      assert Enum.all?(described.nodes, &Map.has_key?(&1, :uuid))
    end

    test "get_flow distinguishes an unknown flow from a missing revision", %{
      user: user,
      flow: flow
    } do
      assert {:error, unknown} = Tools.run("get_flow", %{"flow_id" => 999_999}, user)
      assert unknown == "No flow with id 999999 exists in this organisation."

      assert {:error, unpublished} =
               Tools.run("get_flow", %{"flow_id" => flow.id}, user)

      assert unpublished =~ "exists but has no published revision"
    end

    test "get_flow returns only the structure unless more is asked for", %{
      user: user,
      flow: flow
    } do
      assert {:ok, described} =
               Tools.run(
                 "get_flow",
                 %{"flow_id" => flow.id, "status" => "draft"},
                 user,
                 modules()
               )

      for extra <- [:contacts, :counts, :results, :webhooks],
          do: refute(Map.has_key?(described, extra))
    end

    test "get_flow includes only the extras asked for", %{
      user: user,
      flow: flow
    } do
      assert {:ok, described} =
               Tools.run(
                 "get_flow",
                 %{"flow_id" => flow.id, "status" => "draft", "include" => ["contacts"]},
                 user,
                 modules()
               )

      assert %{waiting_at_node: _, completed: _, stopped: _} = described.contacts
      refute Map.has_key?(described, :counts)
    end

    test "get_flow answers the whole diagnostic in one call", %{
      user: user,
      flow: flow
    } do
      assert {:ok, described} =
               Tools.run(
                 "get_flow",
                 %{
                   "flow_id" => flow.id,
                   "status" => "draft",
                   "include" => ["contacts", "counts", "results", "webhooks"]
                 },
                 user,
                 modules()
               )

      assert %{contacts: _, counts: _, results: _, webhooks: _} = described
      assert is_list(described.nodes)
    end

    test "a flow larger than the limit says so instead of returning a slice", %{
      user: user,
      flow: flow
    } do
      definition = %{
        "nodes" =>
          Enum.map(1..30, fn i ->
            %{"uuid" => "node-#{i}", "actions" => [], "exits" => []}
          end)
      }

      FlowRevision
      |> Ecto.Query.where([r], r.flow_id == ^flow.id)
      |> Repo.update_all(set: [definition: definition, status: "draft"])

      assert {:ok, whole} =
               Tools.run("get_flow", %{"flow_id" => flow.id, "status" => "draft"}, user)

      assert is_list(whole.nodes)
      assert length(whole.nodes) == 30

      assert {:ok, part} =
               Tools.run(
                 "get_flow",
                 %{"flow_id" => flow.id, "status" => "draft", "limit" => 10},
                 user
               )

      assert %{truncated: true, of: 30} = part.nodes
      assert length(part.nodes.showing) == 10
    end

    test "an unknown include value is refused rather than ignored", %{
      user: user,
      flow: flow
    } do
      assert {:error, message} =
               Tools.run(
                 "get_flow",
                 %{"flow_id" => flow.id, "include" => ["nope"]},
                 user,
                 modules()
               )

      assert message =~ ~s(invalid list in :include option)
      assert message =~ ~s(got: "nope")
    end

    test "list_webhook_logs returns the calls a flow made", %{user: user} do
      Fixtures.webhook_log_fixture(%{organization_id: 1})

      assert {:ok, logs} = Tools.run("list_webhook_logs", %{}, user)
      assert Enum.any?(logs, &is_binary(&1.url))
    end
  end

  describe "every tool runs" do
    test "each tool returns data rather than an error", %{
      user: user,
      contact: contact,
      flow: flow,
      assistant: assistant,
      wa_group: wa_group
    } do
      Fixtures.contacts_field_fixture(%{organization_id: 1, name: "Age", shortcode: "age"})

      args = %{
        "get_contact" => %{"contact_id" => contact.id},
        "get_flow" => %{"flow_id" => flow.id, "status" => "draft"},
        "list_reference" => %{"kind" => "tags"},
        "get_group_chat" => %{"wa_group_id" => wa_group.id},
        "get_assistant" => %{"assistant_id" => assistant.id}
      }

      failures =
        for spec <- Tools.all(),
            spec.name not in ["writing_tool", "raising_tool"],
            result = Tools.run(spec.name, Map.get(args, spec.name, %{}), user),
            match?({:error, _}, result) do
          {spec.name, result}
        end

      assert failures == []
    end

    test "get_assistant and the id-only tools explain a missing id", %{
      user: user
    } do
      assert {:error, message} =
               Tools.run("get_assistant", %{"assistant_id" => 999_999}, user)

      assert message == "No assistant with id 999999 exists in this organisation."
    end

    # A spec with no matching `run/2` clause raises rather than answering, and it
    # is only reachable through the name in the spec, so check every one.
    test "every declared tool has a matching run clause", %{user: user} do
      for spec <- Tools.all(), spec.name not in ["writing_tool", "raising_tool"] do
        assert {:ok, {module, _}} = Tools.fetch(spec.name)

        refute match?(
                 {:error, "The lookup failed: no function clause matching" <> _},
                 Tools.run(spec.name, %{}, user)
               ),
               "#{module}.run/2 has no clause for #{spec.name}"
      end
    end

    test "phone numbers leave masked, never in full", %{
      user: user,
      contact: contact
    } do
      assert {:ok, described} =
               Tools.run("get_contact", %{"contact_id" => contact.id}, user)

      refute described.phone == contact.phone
      assert described.phone =~ "******"
      assert String.starts_with?(described.phone, String.slice(contact.phone, 0, 4))

      assert {:ok, [_ | _] = contacts} = Tools.run("list_contacts", %{}, user)
      for one <- contacts, is_binary(one.phone), do: assert(one.phone =~ "******")
    end

    test "a contact is still findable by full phone, and by the id it returns", %{
      user: user,
      contact: contact
    } do
      assert {:ok, found} = Tools.run("get_contact", %{"phone" => contact.phone}, user)
      assert found.id == contact.id
      assert {:ok, _} = Tools.run("get_contact", %{"contact_id" => found.id}, user)
    end

    test "get_contact returns the contact's own field values", %{
      user: user,
      contact: contact
    } do
      assert {:ok, described} =
               Tools.run("get_contact", %{"contact_id" => contact.id}, user)

      assert Map.has_key?(described, :fields)
    end

    test "list_reference covers every kind it advertises", %{user: user} do
      for kind <- Reference.kinds() do
        assert {:ok, rows} = Tools.run("list_reference", %{"kind" => kind}, user)
        assert is_list(rows), "kind #{kind} did not return a list"
      end

      assert {:error, message} = Tools.run("list_reference", %{"kind" => "nope"}, user)
      assert message =~ "invalid value for :kind option"
    end

    test "get_group_chat reads a group's messages and members", %{
      user: user,
      wa_group: group
    } do
      assert {:ok, described} =
               Tools.run(
                 "get_group_chat",
                 %{"wa_group_id" => group.id, "include" => ["messages", "members"]},
                 user,
                 modules()
               )

      assert described.label == group.label
      assert is_list(described.messages)
      assert is_list(described.members)
    end

    test "get_group_chat says so when the group does not exist", %{user: user} do
      assert {:error, message} =
               Tools.run("get_group_chat", %{"wa_group_id" => 999_999}, user)

      assert message == "No group chat with id 999999 exists in this organisation."
    end

    defp form(name) do
      %WhatsappForm{}
      |> WhatsappForm.changeset(%{
        name: name,
        organization_id: 1,
        status: "published",
        meta_flow_id: "meta_#{System.unique_integer([:positive])}"
      })
      |> Repo.insert!()
    end

    defp responses(form, contact, n) do
      for i <- 1..n do
        %WhatsappFormResponse{}
        |> WhatsappFormResponse.changeset(%{
          whatsapp_form_id: form.id,
          contact_id: contact.id,
          organization_id: 1,
          raw_response: %{"answer" => "n#{i}"},
          submitted_at: DateTime.add(~U[2026-01-01 00:00:00Z], i, :second)
        })
        |> Repo.insert!()
      end
    end

    test "a busy form does not starve a quiet one, and totals are truthful" do
      user = Fixtures.user_fixture(%{organization_id: 1})
      contact = Fixtures.contact_fixture(%{organization_id: 1})

      busy = form("Busy form")
      quiet = form("Quiet form")
      responses(busy, contact, 30)
      responses(quiet, contact, 3)

      {:ok, forms} = Tools.run("list_forms", %{"include" => ["responses"]}, user)
      by_name = Map.new(forms, &{&1.name, &1.responses})

      assert %{truncated: true, of: 30} = by_name["Busy form"]
      assert length(by_name["Busy form"].showing) == 25
      assert length(by_name["Quiet form"]) == 3
    end

    test "platform_health never returns credential values", %{user: user} do
      assert {:ok, %{providers: providers, notifications: _, bigquery: _}} =
               Tools.run("platform_health", %{}, user)

      for provider <- providers do
        refute Map.has_key?(provider, :keys)
        refute Map.has_key?(provider, :secrets)
        assert Map.has_key?(provider, :is_active)
      end
    end
  end
end
