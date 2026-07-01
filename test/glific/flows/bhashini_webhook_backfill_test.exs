defmodule Glific.Flows.BhashiniWebhookBackfillTest do
  @moduledoc """
  Unit tests for the pure `migrate_definition/1` transform used by the
  `20260701000000_backfill_deprecated_bhashini_webhooks.exs` migration.

  Uses a trimmed fixture modeled on the deleted `bhasini_asr.json` /
  `bhashini_text_to_speech.json` template flows (recovered from git history at
  `c11cb046d~1`) so the test exercises the same shapes real customized flows
  would have: a `call_webhook` action with the deprecated url + legacy body
  keys, a downstream `send_msg` referencing the old STT result field, a
  downstream attachment referencing the old TTS media field, a downstream
  `send_msg` referencing the old (now-gapped) TTS translation field, and a
  localization override repeating the STT reference.
  """
  use Glific.DataCase, async: true

  alias Glific.{
    Fixtures,
    Flows.BhashiniWebhookBackfill,
    Flows.FlowRevision,
    Repo,
    Users
  }

  @stt_action %{
    "uuid" => "action-stt",
    "type" => "call_webhook",
    "url" => "speech_to_text_with_bhasini",
    "method" => "FUNCTION",
    "result_name" => "voicetotext",
    "headers" => %{"Content-Type" => "application/json"},
    "body" => Jason.encode!(%{"speech" => "@results.voicenote.input", "contact" => "@contact"})
  }

  @tts_action %{
    "uuid" => "action-tts",
    "type" => "call_webhook",
    "url" => "nmt_tts_with_bhasini",
    "method" => "FUNCTION",
    "result_name" => "bhasini_tts",
    "headers" => %{"Content-Type" => "application/json"},
    "body" =>
      Jason.encode!(%{
        "text" => "@results.result_3",
        "source_language" => "english",
        "target_language" => "hindi"
      })
  }

  @fixture_definition %{
    "name" => "Bhashini demo",
    "language" => "base",
    "localization" => %{
      "hi" => %{
        "send-transcription" => %{
          "text" => ["\"@results.voicetotext.asr_response_text\""]
        }
      }
    },
    "nodes" => [
      %{
        "uuid" => "node-stt",
        "actions" => [@stt_action]
      },
      %{
        "uuid" => "send-transcription",
        "actions" => [
          %{
            "uuid" => "send-transcription-action",
            "type" => "send_msg",
            "text" => "@results.voicetotext.asr_response_text",
            "attachments" => []
          }
        ]
      },
      %{
        "uuid" => "node-tts",
        "actions" => [@tts_action]
      },
      %{
        "uuid" => "send-audio",
        "actions" => [
          %{
            "uuid" => "send-audio-action",
            "type" => "send_msg",
            "text" => "",
            "attachments" => ["expression:@results.bhasini_tts.media_url"]
          }
        ]
      },
      %{
        "uuid" => "send-translation",
        "actions" => [
          %{
            "uuid" => "send-translation-action",
            "type" => "send_msg",
            "text" => "@results.bhasini_tts.translated_text",
            "attachments" => []
          }
        ]
      }
    ]
  }

  describe "migrate_definition/1" do
    test "rewrites deprecated webhook urls and strips legacy body keys" do
      {definition, changed?} = BhashiniWebhookBackfill.migrate_definition(@fixture_definition)

      assert changed?

      [stt_action, tts_action] =
        definition["nodes"]
        |> Enum.flat_map(& &1["actions"])
        |> Enum.filter(&(&1["type"] == "call_webhook"))

      assert stt_action["url"] == "speech_to_text"
      assert tts_action["url"] == "text_to_speech"

      stt_body = Jason.decode!(stt_action["body"])
      assert stt_body == %{"speech" => "@results.voicenote.input"}

      tts_body = Jason.decode!(tts_action["body"])
      assert tts_body == %{"text" => "@results.result_3"}
    end

    test "rewrites the downstream STT transcription reference (asr_response_text -> message)" do
      {definition, true} = BhashiniWebhookBackfill.migrate_definition(@fixture_definition)

      send_transcription_action =
        definition["nodes"]
        |> Enum.find(&(&1["uuid"] == "send-transcription"))
        |> Map.fetch!("actions")
        |> hd()

      assert send_transcription_action["text"] == "@results.voicetotext.message"

      # localization override for the same node should be rewritten too
      assert get_in(definition, ["localization", "hi", "send-transcription", "text"]) == [
               "\"@results.voicetotext.message\""
             ]
    end

    test "rewrites the downstream TTS audio attachment reference (media_url -> message)" do
      {definition, true} = BhashiniWebhookBackfill.migrate_definition(@fixture_definition)

      send_audio_action =
        definition["nodes"]
        |> Enum.find(&(&1["uuid"] == "send-audio"))
        |> Map.fetch!("actions")
        |> hd()

      assert send_audio_action["attachments"] == ["expression:@results.bhasini_tts.message"]
    end

    test "does NOT rewrite the dangling translated_text reference (documented gap)" do
      {definition, true} = BhashiniWebhookBackfill.migrate_definition(@fixture_definition)

      send_translation_action =
        definition["nodes"]
        |> Enum.find(&(&1["uuid"] == "send-translation"))
        |> Map.fetch!("actions")
        |> hd()

      assert send_translation_action["text"] == "@results.bhasini_tts.translated_text"
    end

    test "leaves no deprecated webhook name anywhere in the migrated definition" do
      {definition, true} = BhashiniWebhookBackfill.migrate_definition(@fixture_definition)

      refute definition |> Jason.encode!() |> String.contains?("_with_bhasini")
      refute definition |> Jason.encode!() |> String.contains?("nmt_tts")
    end

    test "is idempotent — running the transform again reports nothing left to change" do
      {definition, true} = BhashiniWebhookBackfill.migrate_definition(@fixture_definition)

      assert {^definition, false} = BhashiniWebhookBackfill.migrate_definition(definition)
    end

    test "is a no-op for a flow with no deprecated webhook" do
      clean_definition = %{
        "name" => "clean",
        "nodes" => [
          %{
            "uuid" => "node-1",
            "actions" => [
              %{
                "uuid" => "action-1",
                "type" => "call_webhook",
                "url" => "speech_to_text",
                "result_name" => "voicetotext",
                "body" => Jason.encode!(%{"speech" => "@results.voicenote.input"})
              }
            ]
          }
        ]
      }

      assert {^clean_definition, false} =
               BhashiniWebhookBackfill.migrate_definition(clean_definition)
    end
  end

  describe "run/0" do
    test "backfills a persisted flow_revision referencing a deprecated webhook", %{
      organization_id: organization_id
    } do
      flow = Fixtures.flow_fixture(%{organization_id: organization_id})
      [user | _] = Users.list_users(%{filter: %{organization_id: organization_id}})

      {:ok, flow_revision} =
        %FlowRevision{}
        |> FlowRevision.changeset(%{
          definition: @fixture_definition,
          flow_id: flow.id,
          organization_id: organization_id,
          user_id: user.id,
          revision_number: 0,
          status: "draft"
        })
        |> Repo.insert()

      assert :ok = BhashiniWebhookBackfill.run()

      reloaded = Repo.get!(FlowRevision, flow_revision.id)
      encoded = Jason.encode!(reloaded.definition)

      refute String.contains?(encoded, "_with_bhasini")
      refute String.contains?(encoded, "nmt_tts")
      assert String.contains?(encoded, "\"speech_to_text\"")
      assert String.contains?(encoded, "\"text_to_speech\"")
    end

    test "is a no-op (already applied) when re-run", %{organization_id: organization_id} do
      flow = Fixtures.flow_fixture(%{organization_id: organization_id})
      [user | _] = Users.list_users(%{filter: %{organization_id: organization_id}})

      {:ok, flow_revision} =
        %FlowRevision{}
        |> FlowRevision.changeset(%{
          definition: @fixture_definition,
          flow_id: flow.id,
          organization_id: organization_id,
          user_id: user.id,
          revision_number: 0,
          status: "draft"
        })
        |> Repo.insert()

      assert :ok = BhashiniWebhookBackfill.run()
      first_pass = Repo.get!(FlowRevision, flow_revision.id)

      assert :ok = BhashiniWebhookBackfill.run()
      second_pass = Repo.get!(FlowRevision, flow_revision.id)

      assert first_pass.definition == second_pass.definition
    end

    test "terminates when a revision matches the pattern but has nothing to rewrite",
         %{organization_id: organization_id} do
      flow = Fixtures.flow_fixture(%{organization_id: organization_id})
      [user | _] = Users.list_users(%{filter: %{organization_id: organization_id}})

      # Deprecated webhook name appears only in a sticky-note body (no call_webhook
      # url to rewrite), so the row keeps matching the fetch regex but never
      # changes. The cursor-based runner must still terminate rather than loop.
      stuck_definition = %{
        "nodes" => [],
        "_ui" => %{
          "stickies" => %{
            "note-1" => %{"body" => "TODO: migrate the speech_to_text_with_bhasini node"}
          }
        }
      }

      {:ok, flow_revision} =
        %FlowRevision{}
        |> FlowRevision.changeset(%{
          definition: stuck_definition,
          flow_id: flow.id,
          organization_id: organization_id,
          user_id: user.id,
          revision_number: 0,
          status: "draft"
        })
        |> Repo.insert()

      assert :ok = BhashiniWebhookBackfill.run()

      # unchanged (nothing to rewrite), and crucially the run returned instead of hanging
      reloaded = Repo.get!(FlowRevision, flow_revision.id)
      assert reloaded.definition == stuck_definition
    end
  end
end
