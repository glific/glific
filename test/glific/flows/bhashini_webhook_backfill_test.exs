defmodule Glific.Flows.BhashiniWebhookBackfillTest do
  @moduledoc """
  Tests for the Bhashini template backfill. For every org that still has a
  deprecated Bhashini "Speech to Text" / "Text to Speech" *template* flow, it
  deletes that flow and re-imports the new Kaapi-based templates in its place.
  Template flows only — custom flows are left untouched.
  """
  use Glific.DataCase, async: false

  import Ecto.Query, warn: false

  alias Glific.{
    Fixtures,
    Flows.BhashiniWebhookBackfill,
    Flows.Flow,
    Flows.FlowRevision,
    Repo,
    Users
  }

  # Minimal flow definition that references a deprecated Bhashini FUNCTION webhook.
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

  # Creates a flow (template by default) with a revision referencing the Bhashini webhook.
  defp create_bhashini_flow(organization_id, name, is_template) do
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
        revision_number: 1,
        status: "draft"
      })
      |> Repo.insert()

    flow
  end

  defp latest_definition(flow_id) do
    FlowRevision
    |> where([fr], fr.flow_id == ^flow_id)
    |> order_by([fr], desc: fr.id)
    |> limit(1)
    |> Repo.one()
    |> Map.get(:definition)
    |> Jason.encode!()
  end

  defp flow_count(organization_id, name) do
    Repo.aggregate(
      from(flow in Flow, where: flow.organization_id == ^organization_id and flow.name == ^name),
      :count
    )
  end

  describe "run/0" do
    test "deletes the Bhashini template flow and imports the new STT/TTS templates",
         %{organization_id: organization_id} do
      bhashini_flow = create_bhashini_flow(organization_id, "Bhashini_speech_to_text", true)

      assert :ok = BhashiniWebhookBackfill.run()

      # the old Bhashini template flow is gone
      refute Repo.get(Flow, bhashini_flow.id)

      # the new templates exist and are marked as templates
      speech_to_text =
        Repo.get_by(Flow, %{name: "Speech to Text", organization_id: organization_id})

      text_to_speech =
        Repo.get_by(Flow, %{name: "Text to Speech", organization_id: organization_id})

      assert speech_to_text.is_template
      assert text_to_speech.is_template

      # the new template uses the Kaapi node, never the Bhashini webhook
      definition = latest_definition(speech_to_text.id)
      assert definition =~ "speech_to_text"
      refute definition =~ "_with_bhasini"
    end

    test "leaves a non-template flow that references a deprecated webhook untouched",
         %{organization_id: organization_id} do
      custom_flow = create_bhashini_flow(organization_id, "Custom voice flow", false)

      assert :ok = BhashiniWebhookBackfill.run()

      # untouched, and no new template force-created for this non-affected org
      assert Repo.get(Flow, custom_flow.id)
      assert latest_definition(custom_flow.id) =~ "_with_bhasini"
      assert flow_count(organization_id, "Speech to Text") == 0
    end

    test "is idempotent - a second run does not duplicate the new templates",
         %{organization_id: organization_id} do
      create_bhashini_flow(organization_id, "Bhashini_speech_to_text", true)

      assert :ok = BhashiniWebhookBackfill.run()
      assert :ok = BhashiniWebhookBackfill.run()

      assert flow_count(organization_id, "Speech to Text") == 1
      assert flow_count(organization_id, "Text to Speech") == 1
    end
  end
end
