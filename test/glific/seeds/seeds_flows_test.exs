defmodule Glific.Seeds.SeedsFlowsTest do
  @moduledoc """
  Regression tests for re-seeding the "Speech to Text" / "Text to Speech" template
  flows (replacements for the deleted Bhashini templates). Covers:

  1. `Flows.import_flow/2` — the same import mechanism `SeedsFlows.add_template_flows/1`
     uses per file — successfully imports both new template flows.
  2. Neither flow's definition references a deprecated Bhashini webhook.
  3. `Flow.validate_flow/3` does not raise the "Critical" deprecated-webhook
     migration error for either flow.

  Note: this test exercises `Flows.import_flow/2` directly (rather than the full
  `SeedsFlows.add_template_flows/1`, which sequentially imports all template flow
  files for an organization) because an unrelated, pre-existing template file
  (`clear_variable.json`) collides on flow name with a system flow seeded for every
  organization ("Clear_Variables flow"), which makes the full multi-file import
  fail in a freshly-seeded test organization. That collision is not introduced by
  this change (`add_template_flows/1` is prod-only, so it had never been exercised
  in tests) and is out of scope here.
  """
  use Glific.DataCase

  alias Glific.Flows
  alias Glific.Flows.Flow
  alias Glific.Partners
  alias Glific.Repo
  alias Glific.Seeds.SeedsFlows

  @deprecated_bhashini_webhooks [
    "speech_to_text_with_bhasini",
    "text_to_speech_with_bhasini",
    "nmt_tts_with_bhasini"
  ]

  @template_files ~w(speech_to_text.json text_to_speech.json)
  @template_flow_names %{
    "speech_to_text.json" => "Speech to Text",
    "text_to_speech.json" => "Text to Speech"
  }

  describe "speech_to_text.json / text_to_speech.json template flows" do
    for template_file <- @template_files do
      test "#{template_file} imports cleanly with no deprecated webhook and no Critical validation error",
           %{organization_id: organization_id} do
        template_file = unquote(template_file)
        flow_name = Map.fetch!(@template_flow_names, template_file)

        full_file_path = Path.join(:code.priv_dir(:glific), "data/flows/" <> template_file)
        {:ok, file_content} = File.read(full_file_path)
        {:ok, import_flow} = Jason.decode(file_content)

        assert [%{status: "Successfully imported"}] =
                 Flows.import_flow(import_flow, organization_id)

        {:ok, imported_flow} =
          Repo.fetch_by(Flow, %{name: flow_name, organization_id: organization_id})

        flow = Flow.get_loaded_flow(organization_id, "draft", %{id: imported_flow.id})

        refute_deprecated_webhook(flow.definition)

        errors = Flow.validate_flow(organization_id, "draft", %{id: flow.id})

        refute Enum.any?(errors, fn {_module, _message, severity} -> severity == "Critical" end),
               "expected no Critical validation errors for #{flow_name}, got: #{inspect(errors)}"
      end
    end
  end

  describe "import_template_flow/2" do
    # `SeedsFlows.add_template_flows/1` fans this out to every template file
    # for every organization; exercising it per-file here (rather than the
    # full flow_files list) sidesteps the unrelated clear_variable.json /
    # "Clear_Variables flow" name collision noted in the moduledoc above,
    # while still covering exactly the code path add_template_flows/1 uses.
    for template_file <- @template_files do
      test "imports #{template_file} and marks it as a template",
           %{organization_id: organization_id} do
        template_file = unquote(template_file)
        flow_name = Map.fetch!(@template_flow_names, template_file)
        organization = Partners.organization(organization_id)

        assert {:ok, flow} = SeedsFlows.import_template_flow(organization, template_file)

        assert flow.name == flow_name
        assert flow.is_template

        {:ok, reloaded} =
          Repo.fetch_by(Flow, %{name: flow_name, organization_id: organization_id})

        assert reloaded.is_template
      end
    end
  end

  @spec refute_deprecated_webhook(map()) :: :ok
  defp refute_deprecated_webhook(definition) do
    urls =
      definition["nodes"]
      |> Enum.flat_map(& &1["actions"])
      |> Enum.filter(&(&1["type"] == "call_webhook"))
      |> Enum.map(& &1["url"])

    assert Enum.all?(urls, &(&1 not in @deprecated_bhashini_webhooks)),
           "flow definition still references a deprecated Bhashini webhook: #{inspect(urls)}"

    :ok
  end
end
