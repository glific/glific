defmodule Glific.Scripts.BhashiniTemplateMigrationTest do
  @moduledoc """
  Tests for the Bhashini template migration admin script. For every org that
  still has a deprecated Bhashini "Speech to Text" / "Text to Speech"
  *template* flow (as parsed from its current, `revision_number == 0`,
  definition), it imports the new Kaapi-based templates and only then
  deletes the deprecated flow. Template flows only — custom flows are left
  untouched.
  """
  use Glific.DataCase, async: false

  alias Glific.{
    Fixtures,
    Flows.Flow,
    Flows.FlowRevision,
    Partners,
    Repo,
    Scripts.BhashiniTemplateMigration,
    Users
  }

  # Minimal flow definition that references a deprecated Bhashini FUNCTION webhook,
  # in its current (revision_number 0) revision.
  @bhashini_definition %{
    "name" => "Bhashini_speech_to_text",
    "uuid" => "5021668f-d19b-4b6f-a2a7-986f8f0ddcf0",
    "nodes" => [
      %{
        "uuid" => "node-1",
        "actions" => [
          %{
            "uuid" => "action-1",
            "type" => "call_webhook",
            "url" => "speech_to_text_with_bhasini",
            "method" => "FUNCTION",
            "result_name" => "voicetotext",
            "body" => "{}"
          }
        ],
        "exits" => [%{"uuid" => "exit-1", "destination_uuid" => nil}]
      }
    ]
  }

  # Creates a flow with a revision referencing the deprecated Bhashini webhook.
  # `Fixtures.flow_fixture/1` already inserts a default (empty) revision at
  # revision_number 0; inserting this one afterwards (without specifying
  # revision_number, so the DB default of 0 applies) becomes the new current
  # revision and the DB trigger bumps the default one to 1 — exactly the
  # "current revision" the migration script looks at.
  @spec create_deprecated_flow(non_neg_integer(), String.t(), boolean()) :: Flow.t()
  defp create_deprecated_flow(organization_id, name, is_template) do
    flow =
      Fixtures.flow_fixture(%{
        organization_id: organization_id,
        name: name,
        keywords: [],
        is_template: is_template
      })

    [user | _] = Users.list_users(%{filter: %{organization_id: organization_id}})

    {:ok, _revision} =
      %FlowRevision{}
      |> FlowRevision.changeset(%{
        definition: @bhashini_definition,
        flow_id: flow.id,
        organization_id: organization_id,
        user_id: user.id,
        status: "draft"
      })
      |> Repo.insert()

    flow
  end

  describe "run/1 with dry_run: true" do
    test "lists the deprecated flow(s) and makes no changes", %{organization_id: organization_id} do
      bhashini_flow = create_deprecated_flow(organization_id, "Bhashini_speech_to_text", true)

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert :ok = BhashiniTemplateMigration.run(dry_run: true)
        end)

      assert output =~ to_string(bhashini_flow.id)
      assert output =~ to_string(organization_id)
      assert output =~ bhashini_flow.name

      # no writes: the deprecated flow is untouched and no new template exists
      assert Repo.get(Flow, bhashini_flow.id)
      refute Repo.get_by(Flow, %{name: "Speech to Text", organization_id: organization_id})
      refute Repo.get_by(Flow, %{name: "Text to Speech", organization_id: organization_id})
    end
  end

  describe "run/1" do
    test "deletes the Bhashini template and imports both new templates",
         %{organization_id: organization_id} do
      bhashini_flow = create_deprecated_flow(organization_id, "Bhashini_speech_to_text", true)

      assert :ok = BhashiniTemplateMigration.run(organization_id: organization_id)

      # the old Bhashini template flow is gone
      refute Repo.get(Flow, bhashini_flow.id)

      # the new templates exist and are marked as templates
      speech_to_text =
        Repo.get_by(Flow, %{name: "Speech to Text", organization_id: organization_id})

      text_to_speech =
        Repo.get_by(Flow, %{name: "Text to Speech", organization_id: organization_id})

      assert speech_to_text.is_template
      assert text_to_speech.is_template

      # the new templates use the Kaapi node urls, never the Bhashini webhooks
      assert current_definition_urls(speech_to_text.id) == ["speech_to_text"]
      assert current_definition_urls(text_to_speech.id) == ["text_to_speech"]
    end

    test "leaves a non-deprecated template flow untouched", %{organization_id: organization_id} do
      # A template flow whose current revision is the plain default definition
      # (no call_webhook node at all) — never matches the deprecated pattern.
      other_template =
        Fixtures.flow_fixture(%{
          organization_id: organization_id,
          name: "Other Template",
          keywords: [],
          is_template: true
        })

      assert :ok = BhashiniTemplateMigration.run(organization_id: organization_id)

      assert Repo.get(Flow, other_template.id)
    end

    test "a pre-existing custom (is_template: false) flow with the new template's name does not suppress the import",
         %{organization_id: organization_id} do
      bhashini_flow = create_deprecated_flow(organization_id, "Bhashini_speech_to_text", true)

      # Not a template — the old (rejected) guard matched on name alone and
      # would have treated this as "already migrated". The current guard
      # checks is_template == true, so it does NOT recognize this flow as the
      # new template and still attempts the import, which fails on the
      # (name, organization_id) unique index — proving the guard looked past
      # the name match.
      custom_flow =
        Fixtures.flow_fixture(%{
          organization_id: organization_id,
          name: "Speech to Text",
          keywords: []
        })

      assert :ok = BhashiniTemplateMigration.run(organization_id: organization_id)

      # import failed (name collision) => deletion was skipped entirely, the
      # org is never left without a template
      assert Repo.get(Flow, bhashini_flow.id)

      # the custom flow is untouched, still not a template
      reloaded_custom = Repo.get(Flow, custom_flow.id)
      assert reloaded_custom
      refute reloaded_custom.is_template

      # the halted-on-first-failure text_to_speech template was never imported
      refute Repo.get_by(Flow, %{name: "Text to Speech", organization_id: organization_id})
    end

    test "organization_id: opt only touches the targeted organization",
         %{organization_id: organization_id} do
      org1_flow = create_deprecated_flow(organization_id, "Bhashini_speech_to_text", true)

      org2 = Fixtures.organization_fixture()
      org2_user = Partners.organization(org2.id).root_user
      Repo.put_organization_id(org2.id)
      Repo.put_current_user(org2_user)
      org2_flow = create_deprecated_flow(org2.id, "Bhashini_speech_to_text", true)

      # the script itself sets org context per organization it processes, so
      # switching back here mirrors how it is invoked from a remote console
      Repo.put_organization_id(organization_id)

      assert :ok = BhashiniTemplateMigration.run(organization_id: organization_id)

      # org1 (the targeted org) is fully migrated
      refute Repo.get(Flow, org1_flow.id)

      assert Repo.get_by(Flow, %{
               name: "Speech to Text",
               organization_id: organization_id,
               is_template: true
             })

      # org2 is untouched
      Repo.put_organization_id(org2.id)
      assert Repo.get(Flow, org2_flow.id)
      refute Repo.get_by(Flow, %{name: "Speech to Text", organization_id: org2.id})
    end
  end

  @spec current_definition_urls(non_neg_integer()) :: [String.t()]
  defp current_definition_urls(flow_id) do
    revision = Repo.get_by(FlowRevision, %{flow_id: flow_id, revision_number: 0})

    revision.definition["nodes"]
    |> Enum.flat_map(&Map.get(&1, "actions", []))
    |> Enum.filter(&(&1["type"] == "call_webhook"))
    |> Enum.map(& &1["url"])
    |> Enum.uniq()
  end
end
