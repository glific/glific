defmodule Glific.FLowsTest do
  use Glific.DataCase

  import ExUnit.CaptureLog

  alias Glific.{
    Fixtures,
    Flows,
    Flows.Broadcast,
    Flows.Flow,
    Flows.FlowContext,
    Flows.FlowRevision,
    Flows.MessageBroadcast,
    Groups,
    Messages,
    Messages.Message,
    Processor.ConsumerFlow,
    Processor.ConsumerWorker,
    Repo,
    Seeds.SeedsDev,
    Sheets.Sheet
  }

  describe "flows" do
    @valid_attrs %{
      name: "Test Flow",
      keywords: ["test_keyword"],
      flow_type: :message,
      version_number: "13.1.0"
    }

    @valid_more_attrs %{
      name: "Test Flow More",
      flow_type: :message,
      keywords: ["test_keyword_2"],
      version_number: "13.1.0"
    }

    @invalid_attrs %{
      name: "Test Flow",
      flow_type: :message_2,
      version_number: "13.1.0",
      organization_id: 1
    }

    @update_attrs %{
      name: "Update flow",
      keywords: ["update_keyword"]
    }

    @flow_attrs %{
      name: "Test Flow cache",
      keywords: ["test"],
      flow_type: :message,
      version_number: "13.1.0"
    }

    def flow_fixture(attrs \\ %{}),
      do: Fixtures.flow_fixture(attrs)

    test "list_flows/0 returns all flows", attrs do
      flow = flow_fixture()
      flows = Flows.list_flows(%{filter: attrs})
      assert Enum.filter(flows, fn fl -> fl.name == flow.name end) == [flow]
    end

    test "list_flows/0 with default is_pinned as args should return the searched flow", attrs do
      flow = flow_fixture()
      {:ok, revision} = Repo.fetch_by(FlowRevision, %{flow_id: flow.id})

      revision
      |> Map.take([:definition, :flow_id, :organization_id, :user_id])
      |> Map.merge(%{revision_number: 1})
      |> FlowRevision.create_flow_revision()

      flows =
        Flows.list_flows(%{
          opts: %{order_with: "is_pinned"},
          filter: %{is_active: true, is_template: false, name_or_keyword_or_tags: "testkeyword"},
          organization_id: attrs.organization_id
        })

      assert Enum.count(flows) == 1
    end

    test "list_flows/1 returns flows filtered by keyword", attrs do
      f0 = flow_fixture(@valid_attrs)
      _f1 = flow_fixture(@valid_more_attrs)

      flows = Flows.list_flows(%{filter: Map.merge(attrs, %{keyword: "testkeyword"})})
      assert flows == [f0]

      flows = Flows.list_flows(%{filter: Map.merge(attrs, %{keyword: "wrongkeyword"})})
      assert flows == []

      flows = Flows.list_flows(%{filter: Map.merge(attrs, %{wrong_filter: "test"})})
      assert length(flows) >= 2
    end

    test "list_flows/1 returns flows filtered by tag_id", attrs do
      tag1 = Fixtures.tag_fixture(Map.merge(attrs, %{label: "test_tag"}))

      f0 = flow_fixture(Map.merge(@valid_attrs, %{tag_id: tag1.id}))
      _f1 = flow_fixture(@valid_more_attrs)

      flows = Flows.list_flows(%{filter: Map.merge(attrs, %{tag_ids: [tag1.id]})})
      assert flows == [f0]
    end

    test "list_flows/1 returns flows filtered by is_pinned", attrs do
      flows = Flows.list_flows(%{filter: %{is_pinned: true}})
      old_count = length(flows)

      assert {:ok, %Flow{} = _flow} =
               @valid_attrs
               |> Map.merge(%{
                 organization_id: attrs.organization_id,
                 is_pinned: true
               })
               |> Flows.create_flow()

      flows = Flows.list_flows(%{filter: %{is_pinned: true}})
      assert length(flows) == old_count + 1
    end

    test "list_flows/1 returns flows filtered by is_template", attrs do
      flows_template_true = Flows.list_flows(%{filter: %{is_template: true}})
      old_count_template_true = length(flows_template_true)

      assert {:ok, %Flow{} = _flow_template_true} =
               @valid_attrs
               |> Map.merge(%{
                 organization_id: attrs.organization_id,
                 is_template: true
               })
               |> Flows.create_flow()

      flows_template_true = Flows.list_flows(%{filter: %{is_template: true}})
      assert length(flows_template_true) == old_count_template_true + 1
    end

    test "list_flows/1 returns flows filtered by name keyword", attrs do
      f0 = flow_fixture(@valid_attrs)
      f1 = flow_fixture(@valid_more_attrs |> Map.merge(%{name: "testkeyword"}))

      flows =
        Flows.list_flows(%{
          filter:
            Map.merge(attrs, %{
              is_active: true,
              is_template: false,
              name_or_keyword_or_tags: "testkeyword"
            })
        })

      assert flows == [f0, f1] || flows == [f1, f0]

      flows =
        Flows.list_flows(%{
          filter:
            Map.merge(attrs, %{
              is_active: true,
              is_template: false,
              name_or_keyword_or_tags: "wrongkeyword"
            })
        })

      assert flows == []

      flows = Flows.list_flows(%{filter: Map.merge(attrs, %{wrong_filter: "test"})})
      assert length(flows) >= 2
    end

    test "count_flows/0 returns count of all flows",
         %{organization_id: organization_id} = attrs do
      flow_count =
        Flow
        |> Ecto.Query.where([q], q.organization_id == ^organization_id)
        |> Repo.aggregate(:count)

      _ = flow_fixture()
      assert Flows.count_flows(%{filter: attrs}) == flow_count + 1

      _ = flow_fixture(@valid_more_attrs)
      assert Flows.count_flows(%{filter: attrs}) == flow_count + 2

      assert Flows.count_flows(%{filter: Map.merge(attrs, %{name: "Help Workflow"})}) == 1
    end

    test "count_flows/0 returns count of flows filtered by is_template",
         %{organization_id: organization_id} = attrs do
      initial_count = Flows.count_flows(%{filter: Map.merge(attrs, %{is_template: true})})

      assert {:ok, %Flow{} = _flow} =
               @valid_attrs
               |> Map.merge(%{organization_id: organization_id, is_template: true})
               |> Flows.create_flow()

      assert Flows.count_flows(%{filter: Map.merge(attrs, %{is_template: true})}) ==
               initial_count + 1
    end

    test "get_flow!/1 returns the flow with given id" do
      flow = flow_fixture()
      assert Flows.get_flow!(flow.id) == flow
    end

    test "fetch_flow/1 returns the flow with given id or returns {:ok, flow} or {:error, any}" do
      flow = flow_fixture()
      {:ok, fetched_flow} = Flows.fetch_flow(flow.id)
      assert fetched_flow.name == flow.name
      assert fetched_flow.status == flow.status
      assert fetched_flow.keywords == flow.keywords
    end

    test "create_flow/1 with valid data creates a flow", attrs do
      [predefine_flow | _tail] = Flows.list_flows(%{filter: attrs})

      assert {:ok, %Flow{} = flow} =
               @valid_attrs
               |> Map.merge(%{organization_id: predefine_flow.organization_id})
               |> Flows.create_flow()

      assert flow.name == @valid_attrs.name
      assert flow.flow_type == @valid_attrs.flow_type
      assert flow.keywords == Enum.map(@valid_attrs.keywords, &Glific.string_clean(&1))
    end

    test "create_flow/1 with valid data creates a background flow", attrs do
      [predefine_flow | _tail] = Flows.list_flows(%{filter: attrs})

      assert {:ok, %Flow{} = flow} =
               @valid_attrs
               |> Map.merge(%{
                 organization_id: predefine_flow.organization_id,
                 is_background: true
               })
               |> Flows.create_flow()

      assert flow.name == @valid_attrs.name
      assert flow.is_background == true
      assert flow.flow_type == @valid_attrs.flow_type
      assert flow.keywords == Enum.map(@valid_attrs.keywords, &Glific.string_clean(&1))
    end

    test "create_flow/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Flows.create_flow(@invalid_attrs)
    end

    test "create_flow/1 with existing keyword returns error changeset", attrs do
      attrs = Map.merge(@valid_attrs, attrs)
      Flows.create_flow(attrs)

      invalid_attrs =
        attrs
        |> Map.merge(%{keywords: ["test_keyword", "test_keyword_2"]})

      assert {:error, %Ecto.Changeset{}} = Flows.create_flow(invalid_attrs)
    end

    test "create_flow/1 with keywords will covert all keywords to downcase", attrs do
      attrs = Map.merge(@valid_attrs, attrs)

      assert {:ok, %Flow{} = flow} =
               attrs
               |> Map.merge(%{keywords: ["Test_Keyword", "TEST_KEYWORD_2"]})
               |> Flows.create_flow()

      assert flow.keywords == ["testkeyword", "testkeyword2"]
    end

    test "create_flow/1 will have a default revision" do
      flow = flow_fixture(@valid_attrs)
      flow = Repo.preload(flow, [:revisions])
      assert flow.name == @valid_attrs.name
      assert flow.flow_type == @valid_attrs.flow_type
      assert is_list(flow.revisions)
      assert length(flow.revisions) > 0
    end

    test "update_flow/2 with valid data updates the flow" do
      flow = flow_fixture()
      assert {:ok, %Flow{} = flow} = Flows.update_flow(flow, @update_attrs)
      assert flow.name == @update_attrs.name
    end

    test "update_flow/2 with invalid data returns error changeset" do
      flow = flow_fixture()
      assert {:error, %Ecto.Changeset{}} = Flows.update_flow(flow, @invalid_attrs)
      assert flow == Flows.get_flow!(flow.id)
    end

    test "update_flow/2 with keywords" do
      flow = flow_fixture()

      valid_attrs =
        @valid_attrs
        |> Map.merge(%{keywords: ["test_keyword", "test_keyword_1"]})

      assert {:ok, %Flow{}} = Flows.update_flow(flow, valid_attrs)

      # update flow with existing keyword should return error
      flow = flow_fixture(@valid_more_attrs)

      invalid_attrs =
        @valid_attrs
        |> Map.merge(%{keywords: ["test_keyword_2", "test_keyword_1"]})

      assert {:error, %Ecto.Changeset{}} = Flows.update_flow(flow, invalid_attrs)
    end

    test "delete_flow/1 deletes the flow" do
      flow = flow_fixture()
      assert {:ok, %Flow{}} = Flows.delete_flow(flow)
      assert_raise Ecto.NoResultsError, fn -> Flows.get_flow!(flow.id) end
    end

    test "change_flow/1 returns a flow changeset" do
      flow = flow_fixture()
      assert %Ecto.Changeset{} = Flows.change_flow(flow)
    end

    test "get_flow_revision_list/1 returns a formatted list of flow revisions" do
      flow =
        flow_fixture()
        |> Repo.preload([:revisions])

      revisions = Flows.get_flow_revision_list(flow.uuid).results
      assert length(flow.revisions) == length(revisions)
    end

    test "get_flow_revision/2 returns a specific revision" do
      flow =
        flow_fixture()
        |> Repo.preload([:revisions])

      [revision] = flow.revisions
      assert Flows.get_flow_revision(flow.uuid, revision.id).definition == revision.definition
    end

    test "create_flow_revision/1 create a specific revision for the flow" do
      user = Repo.get_current_user()

      flow =
        flow_fixture()
        |> Repo.preload([:revisions])

      [revision] = flow.revisions

      Flows.create_flow_revision(revision.definition, user.id)
      current_revisions = Flows.get_flow_revision_list(flow.uuid).results
      assert length(current_revisions) == length(flow.revisions) + 1
    end

    test "check_required_fields/1 check the required field in the json file", attrs do
      [flow | _tail] = Flows.list_flows(%{filter: attrs})
      flow = Repo.preload(flow, [:revisions])
      [revision | _tail] = flow.revisions
      assert Flows.check_required_fields(revision.definition, [:name]) == true
      definition = Map.delete(revision.definition, "name")
      assert_raise ArgumentError, fn -> Flows.check_required_fields(definition, [:name]) end
    end

    test "get_cached_flow/2 save the flow to cache returns a tuple and flow",
         %{organization_id: organization_id} = attrs do
      [flow | _tail] = Flows.list_flows(%{filter: attrs})

      {:ok, loaded_flow} =
        Flows.get_cached_flow(organization_id, {:flow_uuid, flow.uuid, "published"})

      assert loaded_flow.nodes != nil
    end

    test "update_cached_flow/1 will remove the keys and update the flows" do
      organization_id = Fixtures.get_org_id()
      [flow | _tail] = Flows.list_flows(%{filter: %{organization_id: organization_id}})

      {:ok, loaded_flow} =
        Flows.get_cached_flow(organization_id, {:flow_uuid, flow.uuid, "published"})

      Flows.update_flow(flow, %{:keywords => ["flow_new"]})
      Flows.update_cached_flow(flow, "published")

      {:ok, loaded_flow_new} =
        Flows.get_cached_flow(organization_id, {:flow_uuid, flow.uuid, "published"})

      assert loaded_flow.keywords == flow.keywords
      assert loaded_flow_new.keywords != loaded_flow.keywords
    end

    test "publish_flow/1 updates the latest flow revision status",
         %{organization_id: organization_id} = _attrs do
      user = Repo.get_current_user()

      SeedsDev.seed_test_flows()

      name = "Language Workflow"
      {:ok, flow} = Repo.fetch_by(Flow, %{name: name, organization_id: organization_id})
      flow = Repo.preload(flow, [:revisions])

      # should set status of recent flow revision as "published"
      assert {:ok, %Flow{}} = Flows.publish_flow(flow, user.id)

      {:ok, revision} =
        FlowRevision
        |> Repo.fetch_by(%{flow_id: flow.id, revision_number: 0})

      assert revision.status == "published"

      [revision] = flow.revisions
      # should update the cached flow definition
      {:ok, loaded_flow} =
        Flows.get_cached_flow(organization_id, {:flow_uuid, flow.uuid, "published"})

      assert loaded_flow.definition == revision.definition

      # If a flow revision is already published
      # should reset previously published flow revision and set status of recent one as "published"
      new_definition = revision.definition |> Map.merge(%{"revision" => 2})
      Flows.create_flow_revision(new_definition, user.id)

      assert {:ok, %Flow{}} = Flows.publish_flow(flow, user.id)

      {:ok, revision} =
        FlowRevision
        |> Repo.fetch_by(%{flow_id: flow.id, revision_number: 0})

      assert revision.status == "published"

      # should update the cached flow definition
      {:ok, loaded_flow} =
        Flows.get_cached_flow(organization_id, {:flow_uuid, flow.uuid, "published"})

      assert loaded_flow.definition == new_definition
    end

    test "start_contact_flow/2 will setup the flow for a contact", attrs do
      [flow | _tail] = Flows.list_flows(%{filter: attrs})
      # Refreshing the cache which might be updated in other test cases.
      assert {:ok, %Flow{} = flow} = Flows.update_flow(flow, %{is_active: true})
      contact = Fixtures.contact_fixture(attrs)

      {:ok, flow} = Flows.start_contact_flow(flow, contact)

      first_action = hd(hd(flow.nodes).actions)

      assert {:ok, _message} =
               Repo.fetch_by(Message, %{uuid: first_action.node_uuid, contact_id: contact.id})
    end

    test "start_contact_flow/2 if flow is not available", attrs do
      contact = Fixtures.contact_fixture(attrs)

      {:error, error} = Flows.start_contact_flow(9999, contact)

      assert get_in(error, [Access.at(1)]) == "Flow not found"
    end

    test "start_contact_flow/2 if flow is not active", attrs do
      [flow | _tail] = Flows.list_flows(%{filter: attrs})

      contact = Fixtures.contact_fixture(attrs)

      assert {:ok, %Flow{} = flow} = Flows.update_flow(flow, %{is_active: false})

      {:error, error} = Flows.start_contact_flow(flow.id, contact)
      assert get_in(error, [Access.at(1)]) == "Flow is not active"

      assert {:ok, _flow} = Flows.update_flow(flow, %{is_active: true})
    end

    test "start_contact_flow/2 will setup the template flow for a contact", attrs do
      SeedsDev.seed_session_templates()
      [flow | _tail] = Flows.list_flows(%{filter: %{name: "Template Workflow"}})
      contact = Fixtures.contact_fixture(attrs)
      Flows.start_contact_flow(flow, contact)

      assert {:ok, _flow_context} =
               Repo.fetch_by(FlowContext, %{flow_id: flow.id, contact_id: contact.id})
    end

    test "start_group_flow/2 will setup the flow for a group of contacts", attrs do
      [flow | _tail] = Flows.list_flows(%{filter: attrs})
      group = Fixtures.group_fixture()
      contact = Fixtures.contact_fixture()
      contact2 = Fixtures.contact_fixture()
      default_results = %{key: "value"}

      Groups.create_contact_group(%{
        group_id: group.id,
        contact_id: contact.id,
        organization_id: attrs.organization_id
      })

      Groups.create_contact_group(%{
        group_id: group.id,
        contact_id: contact2.id,
        organization_id: attrs.organization_id
      })

      {:ok, flow} = Flows.start_group_flow(flow, [group.id], default_results)

      assert {:ok, message_broadcast} =
               Repo.fetch_by(MessageBroadcast, %{
                 group_id: group.id,
                 flow_id: flow.id
               })

      assert message_broadcast.completed_at == nil

      # lets sleep for 3 seconds, to ensure that messages have been delivered
      Broadcast.execute_broadcasts(attrs.organization_id)
      Process.sleep(3_000)

      first_action = hd(hd(flow.nodes).actions)

      assert {:ok, _message} =
               Repo.fetch_by(Message, %{uuid: first_action.node_uuid, contact_id: contact.id})

      assert {:ok, _message} =
               Repo.fetch_by(Message, %{uuid: first_action.node_uuid, contact_id: contact2.id})

      Broadcast.execute_broadcasts(attrs.organization_id)

      assert {:ok, message_broadcast} =
               Repo.fetch_by(MessageBroadcast, %{
                 group_id: group.id,
                 flow_id: flow.id
               })

      assert message_broadcast.completed_at != nil

      broadcast_results = message_broadcast.default_results
      assert broadcast_results["key"] == default_results.key
    end

    test "copy_flow/2 with valid data makes a copy of flow" do
      flow = flow_fixture()

      attrs = %{
        name: "copied flow",
        keywords: []
      }

      assert {:ok, %Flow{} = copied_flow} = Flows.copy_flow(flow, attrs)
      assert copied_flow.name == attrs.name

      # it should create a copy of flow revision
      {:ok, flow_revision} = Repo.fetch_by(FlowRevision, %{flow_id: flow.id, revision_number: 0})

      assert {:ok, copied_flow_revision} =
               Repo.fetch_by(FlowRevision, %{flow_id: copied_flow.id, revision_number: 0})

      assert copied_flow_revision.definition ==
               flow_revision.definition |> Map.merge(%{"uuid" => copied_flow.uuid})

      # copy a flow without a name gives an error
      assert {:error, %Ecto.Changeset{}} = Flows.copy_flow(flow, %{})
    end

    test "import_flow/2 links valid google sheet actions",
         %{organization_id: organization_id} do
      mock_google_sheet_requests()

      flow_name = unique_import_flow_name("valid-sheet")
      sheet_url = valid_google_sheet_url()

      import_flow = import_flow_payload([flow_revision_with_sheet_action(flow_name, sheet_url)])

      assert [%{flow_name: ^flow_name, status: "Successfully imported"}] =
               Flows.import_flow(import_flow, organization_id)

      assert {:ok, sheet} = Repo.fetch_by(Sheet, %{url: sheet_url})

      action = imported_google_sheet_action(flow_name)
      assert action["sheet_id"] == sheet.id
    end

    test "import_flow/2 preserves sheet_id and logs a warning for invalid google sheet URLs",
         %{organization_id: organization_id} do
      mock_google_sheet_requests()

      flow_name = unique_import_flow_name("invalid-sheet")
      sheet_url = "Add Sheet URL"

      import_flow =
        import_flow_payload([
          flow_revision_with_sheet_action(flow_name, sheet_url, sheet_id: 1234)
        ])

      log =
        capture_log(fn ->
          assert [%{flow_name: ^flow_name, status: "Successfully imported"}] =
                   Flows.import_flow(import_flow, organization_id)
        end)

      action = imported_google_sheet_action(flow_name)
      assert Map.has_key?(action, "sheet_id")
      assert is_nil(action["sheet_id"])
      assert log =~ "Unable to create Google Sheet while importing flow action"
      assert log =~ sheet_url

      assert {:ok, flow} = Repo.fetch_by(Flow, %{name: flow_name})
      assert %Flow{} = Flow.get_loaded_flow(organization_id, "draft", %{id: flow.id})
      assert is_list(Flow.validate_flow(organization_id, "draft", %{id: flow.id}))
    end

    test "import_flow/2 continues importing a batch when one google sheet URL is invalid",
         %{organization_id: organization_id} do
      mock_google_sheet_requests()

      invalid_flow_name = unique_import_flow_name("batch-invalid-sheet")
      valid_flow_name = unique_import_flow_name("batch-valid-sheet")
      valid_sheet_url = valid_google_sheet_url()

      import_flow =
        import_flow_payload([
          flow_revision_with_sheet_action(invalid_flow_name, "Add Sheet URL", sheet_id: 1234),
          flow_revision_with_sheet_action(valid_flow_name, valid_sheet_url)
        ])

      log =
        capture_log(fn ->
          assert [
                   %{flow_name: ^invalid_flow_name, status: "Successfully imported"},
                   %{flow_name: ^valid_flow_name, status: "Successfully imported"}
                 ] = Flows.import_flow(import_flow, organization_id)
        end)

      assert log =~ "Add Sheet URL"
      assert {:ok, _flow} = Repo.fetch_by(Flow, %{name: invalid_flow_name})
      assert {:ok, _flow} = Repo.fetch_by(Flow, %{name: valid_flow_name})

      invalid_action = imported_google_sheet_action(invalid_flow_name)
      valid_action = imported_google_sheet_action(valid_flow_name)

      assert Map.has_key?(invalid_action, "sheet_id")
      assert is_nil(invalid_action["sheet_id"])
      assert is_integer(valid_action["sheet_id"])
    end

    test "flow keyword map keys are always in lower case", attrs do
      flow = flow_fixture()

      assert {:ok, %Flow{} = flow} =
               Flows.update_flow(flow, %{keywords: ["Hello", "Greetings", "ABCD"]})

      keyword_map = Flows.flow_keywords_map(attrs.organization_id)

      assert nil ==
               Enum.find(keyword_map[flow.status], fn {keyword, _flow_id} ->
                 keyword != Glific.string_clean(keyword)
               end)
    end
  end

  defp mock_google_sheet_requests do
    Tesla.Mock.mock(fn
      %{method: :get, url: "Add Sheet URL"} ->
        {:error, :invalid_url}

      %{method: :get, url: url} when is_binary(url) ->
        if String.contains?(url, "export?format=csv") do
          %Tesla.Env{
            status: 200,
            body: "Key,Day,Message English\r\nwelcome,1,Hello"
          }
        else
          {:error, :unexpected_url}
        end
    end)
  end

  defp import_flow_payload(flow_revisions) do
    %{
      "flows" => flow_revisions,
      "contact_field" => [],
      "collections" => [],
      "interactive_templates" => []
    }
  end

  defp flow_revision_with_sheet_action(flow_name, sheet_url, opts \\ []) do
    flow_uuid = Ecto.UUID.generate()
    node_uuid = Ecto.UUID.generate()

    action =
      %{
        "uuid" => Ecto.UUID.generate(),
        "type" => "link_google_sheet",
        "name" => "#{flow_name} sheet",
        "url" => sheet_url,
        "action_type" => "READ",
        "result_name" => "sheet_result",
        "sheet_id" => Keyword.get(opts, :sheet_id)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    %{
      "definition" => %{
        "name" => flow_name,
        "uuid" => flow_uuid,
        "spec_version" => "13.1.0",
        "language" => "base",
        "type" => "messaging",
        "nodes" => [
          %{
            "uuid" => node_uuid,
            "actions" => [action],
            "exits" => []
          }
        ],
        "_ui" => %{
          "nodes" => %{
            node_uuid => %{
              "position" => %{
                "top" => 0,
                "left" => 0
              }
            }
          }
        },
        "localization" => %{},
        "revision" => 1,
        "expire_after_minutes" => 10_080
      },
      "keywords" => []
    }
  end

  defp imported_google_sheet_action(flow_name) do
    {:ok, flow} = Repo.fetch_by(Flow, %{name: flow_name})

    revision =
      FlowRevision
      |> where([fr], fr.flow_id == ^flow.id)
      |> order_by([fr], desc: fr.id)
      |> limit(1)
      |> Repo.one!()

    revision.definition
    |> Map.get("nodes", [])
    |> Enum.flat_map(fn node -> node["actions"] || [] end)
    |> Enum.find(fn action -> action["type"] == "link_google_sheet" end)
  end

  defp unique_import_flow_name(prefix) do
    "#{prefix}-#{System.unique_integer([:positive])}"
  end

  defp valid_google_sheet_url do
    "https://docs.google.com/spreadsheets/d/#{Ecto.UUID.generate()}/edit#gid=0"
  end

  defp expected_error(str) do
    errors = [
      "Your flow has dangling nodes",
      "Could not find Contact:",
      "Could not find Group:",
      "The next message after a long wait for time should be a template",
      "Could not find Sub Flow:",
      "Could not parse",
      "\"newcontact\" has already been used as a keyword for a flow",
      "The next message after a long no response should be a template",
      "An Interactive template does not exist",
      "A template could not be found in the flow",
      "Language is a required field",
      "The next node after interactive Node 731b should be wait for response",
      "Node af33 is missing translations in Hindi",
      "Node 3964 is missing translations in Hindi",
      "Node a0f7 is missing translations in Hindi",
      "Node bc66 is missing translations in Hindi",
      "Node cee6 is missing translations in Hindi",
      "is missing template translations in Hindi"
    ]

    Enum.any?(errors, &String.contains?(str, &1))
  end

  test "test validate and response_other on test workflow" do
    SeedsDev.seed_test_flows()

    {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})

    errors =
      Flow.validate_flow(flow.organization_id, "draft", %{id: flow.id})

    assert is_list(errors)

    Enum.each(
      errors,
      fn e -> assert expected_error(elem(e, 1)) end
    )
  end

  test "test not setting other option on test workflow",
       %{organization_id: organization_id} = _attrs do
    SeedsDev.seed_test_flows()

    contact = Fixtures.contact_fixture()

    opts = [
      contact_id: contact.id,
      sender_id: contact.id,
      receiver_id: contact.id,
      flow: :inbound
    ]

    message = Messages.create_temp_message(organization_id, "some random message", opts)

    message_count = Repo.aggregate(Message, :count)

    {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})
    {:ok, flow} = Flows.update_flow(flow, %{respond_other: true})

    {:ok, flow} = Flows.get_cached_flow(organization_id, {:flow_uuid, flow.uuid, "published"})

    {:ok, context} = FlowContext.seed_context(flow, contact, "published")

    context |> FlowContext.load_context(flow) |> FlowContext.execute([message])
    new_count = Repo.aggregate(Message, :count)

    assert message_count < new_count
    # since we should have recd 2 messages, hello and hello
    assert message_count + 2 == new_count
  end

  test "test executing the new contact workflow and ensuring parent and child are set",
       %{organization_id: organization_id} = _attrs do
    contact = Fixtures.contact_fixture()

    message_count = Repo.aggregate(Message, :count)
    context_count = Repo.aggregate(FlowContext, :count)

    {:ok, flow} = Repo.fetch_by(Flow, %{name: "New Contact Workflow"})
    {:ok, flow} = Flows.get_cached_flow(organization_id, {:flow_uuid, flow.uuid, "published"})

    {:ok, context} = FlowContext.seed_context(flow, contact, "published")

    {:ok, context, _msgs} =
      context
      |> FlowContext.load_context(flow)
      |> FlowContext.execute([])

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "status" => "submitted",
              "messageId" => Faker.String.base64(36)
            })
        }
    end)

    state = ConsumerWorker.load_state(organization_id)

    message = Fixtures.message_fixture(%{body: "👍", sender_id: contact.id})
    ConsumerWorker.process_message(message, state)

    message = Fixtures.message_fixture(%{body: "2", sender_id: contact.id})
    ConsumerWorker.process_message(message, state)

    db_context = Repo.get!(FlowContext, context.id)
    assert !is_nil(db_context.results)
    assert !is_nil(db_context.results["child"])

    child_context =
      FlowContext
      |> where([fc], is_nil(fc.completed_at))
      |> where([fc], fc.parent_id == ^context.id)
      |> Repo.one!()

    assert !is_nil(child_context.results)
    assert !is_nil(child_context.results["parent"])

    assert message_count < Repo.aggregate(Message, :count)
    assert context_count < Repo.aggregate(FlowContext, :count)
  end

  test "publishing multiple flow revision of a same flow throws and error",
       %{organization_id: organization_id} = _attrs do
    SeedsDev.seed_test_flows()
    user = Repo.get_current_user()
    name = "Language Workflow"
    {:ok, flow} = Repo.fetch_by(Flow, %{name: name, organization_id: organization_id})
    flow = Repo.preload(flow, [:revisions])

    # should set status of recent flow revision as "published"
    assert {:ok, %Flow{}} = Flows.publish_flow(flow, user.id)

    {:ok, revision} =
      FlowRevision
      |> Repo.fetch_by(%{flow_id: flow.id, revision_number: 0})

    assert revision.status == "published"

    [flow_revision | _tail] =
      FlowRevision
      |> where([fr], fr.flow_id == ^flow.id)
      |> Repo.all()

    assert {:error, %Ecto.Changeset{}} =
             flow_revision
             |> FlowRevision.changeset(%{status: "published", revision_number: 0})
             |> Repo.update()
  end

  test "start_group_flow/4 returns an error when no group IDs are provided", attrs do
    [flow | _tail] = Flows.list_flows(%{filter: attrs})
    default_results = %{key: "value"}

    {:error, message} = Flows.start_group_flow(flow, [], default_results)
    assert message == "Group ID is empty"
  end

  test "copy_flow/2 with valid data makes a copy of a template flow",
       %{organization_id: organization_id} = _attrs do
    user = Repo.get_current_user()
    name = "Language Workflow"

    {:ok, flow} = Repo.fetch_by(Flow, %{name: name, organization_id: organization_id})
    flow = Repo.preload(flow, [:revisions])
    flow = Map.merge(flow, %{is_template: true})

    attrs = %{
      name: "copied flow",
      keywords: ["temp"]
    }

    {:ok, temp_flow} = Flows.copy_flow(flow, attrs)
    assert temp_flow.name == attrs.name
    assert temp_flow.is_template == false
    temp_flow = Repo.preload(temp_flow, [:revisions])
    {:ok, temp_flow} = Flows.publish_flow(temp_flow, user.id)

    {:ok, revision} =
      FlowRevision
      |> Repo.fetch_by(%{flow_id: temp_flow.id, revision_number: 0})

    assert revision.status == "published"

    # check if the keyword is starting a flow
    state = ConsumerFlow.load_state(Fixtures.get_org_id())
    body = hd(attrs.keywords)

    # keep track of current messages
    message_count = Repo.aggregate(Message, :count)

    sender = Fixtures.contact_fixture(%{organization_id: organization_id})

    message =
      Fixtures.message_fixture(%{body: body, sender_id: sender.id})
      |> Repo.preload([:contact])

    ConsumerFlow.process_message({message, state}, message.body)

    new_message_count = Repo.aggregate(Message, :count)
    assert new_message_count > message_count + 1
  end

  test "get_cached_flow/3 should return the skip_validation field in flow cache",
       %{organization_id: organization_id} = _attrs do
    {:ok, flow} =
      @flow_attrs
      |> Map.merge(%{
        organization_id: organization_id,
        skip_validation: true
      })
      |> Flows.create_flow()

    flow = Repo.preload(flow, [:revisions])

    [revision] = flow.revisions

    revision
    |> Ecto.Changeset.change(status: "published")
    |> Repo.update()

    {:ok, loaded_flow} =
      Flows.get_cached_flow(organization_id, {:flow_uuid, flow.uuid, "published"})

    assert loaded_flow.skip_validation == true
  end

  test "publish_flow/1 handles invalid expression errors",
       %{organization_id: organization_id} = _attrs do
    user = Repo.get_current_user()

    SeedsDev.seed_test_flows()

    name = "Invalid expression"
    {:ok, flow} = Repo.fetch_by(Flow, %{name: name, organization_id: organization_id})
    flow = Repo.preload(flow, [:revisions])

    assert {:errors, errors} = Flows.publish_flow(flow, user.id)

    # In this flow there are 3 split-by expressions in which 2 of them are not valid/unsupported
    assert Enum.count(errors, fn error ->
             error.category == "Critical" and String.contains?(error.message, "expression")
           end) == 2
  end
end
