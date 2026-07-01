defmodule Glific.Flows.BhashiniWebhookBackfill do
  @moduledoc """
  One-shot, idempotent backfill that migrates existing `flow_revisions` off the
  removed Bhashini FUNCTION webhooks (`speech_to_text_with_bhasini`,
  `text_to_speech_with_bhasini`, `nmt_tts_with_bhasini`) onto their async Kaapi
  replacements (`speech_to_text`, `text_to_speech`). Publishing a flow that still
  references a deprecated webhook raises a "Critical" validation error (see
  `Glific.Flows.Action`'s `@deprecated_bhashini_webhooks` / `validate/3`); this
  backfill lets already-imported/customized flows publish cleanly again without
  requiring every organization to hand-edit their flow.

  Run from the `20260701000000_backfill_deprecated_bhashini_webhooks.exs`
  migration via `run/0`.

  ## What this DOES rewrite (deterministic, safe for customized flows)

    * The `call_webhook` action's `url` — deprecated name -> replacement.
    * The action's `body` — drops the now-meaningless legacy keys the old
      Bhashini API required (`contact`, `source_language`, `target_language`).
      The `speech` / `text` key (the only field the new node reads) is left
      exactly as the organization wrote it, since both the old and new webhook
      contracts use the same key name for it.
    * Downstream `@results.<result_name>.asr_response_text` references (the old
      STT transcription field) -> `@results.<result_name>.message`, which is
      where `Glific.Flows.Webhook.resume/4` now places the transcription.
    * Downstream `@results.<result_name>.media_url` references (the old TTS
      audio attachment field) -> `@results.<result_name>.message`, which is
      where the uploaded TTS audio URL now lands
      (`Glific.Flows.Webhook.maybe_upload_tts_audio/1`).

  ## What this does NOT rewrite (documented gap, needs manual review)

  The old Bhashini TTS flow translated text (English -> target language) via
  `nmt_tts_with_bhasini` and then spoke the *translated* text, exposing the
  translation as `@results.<result_name>.translated_text` in a `send_msg` text
  node. The new `text_to_speech` node has no translation step — it only speaks
  back the text it is given — so there is no equivalent value to substitute in
  automatically (substituting the new audio URL in a plain text field would
  silently send a raw media URL as message text, which is arguably worse than
  leaving the reference dangling). This backfill leaves `.translated_text`
  references untouched and logs a warning (via `Glific.log_error/2`) naming the
  affected `flow_revision.id` so the organization can review and rewrite the
  node by hand.

  This backfill only touches `draft` and `published` revisions — archived
  history is left as-is.
  """

  require Logger

  import Ecto.Query, warn: false

  alias Glific.{Flows.FlowRevision, Repo}

  @deprecated_webhooks %{
    "speech_to_text_with_bhasini" => {"speech_to_text", :stt},
    "text_to_speech_with_bhasini" => {"text_to_speech", :tts},
    "nmt_tts_with_bhasini" => {"text_to_speech", :tts}
  }

  # Keys the old Bhashini API required that the new nodes simply ignore.
  @stt_legacy_body_keys ["contact"]
  @tts_legacy_body_keys ["contact", "source_language", "target_language"]

  @batch_size 200

  @doc """
  Cross-org entry point. Walks matching flow_revisions in ascending-id batches,
  rewriting and persisting each, and stops once no more rows lie past the cursor.

  The cursor (rather than re-querying the shrinking match set) guarantees forward
  progress and termination even for a revision that matches the pattern but can't
  be rewritten to drop it — e.g. a customized flow that also mentions a deprecated
  webhook name in a sticky note or message text, which the url rewrite won't
  touch. Re-running is safe (idempotent): already-migrated rows no longer match.
  """
  @spec run() :: :ok
  def run, do: run(0)

  @spec run(non_neg_integer()) :: :ok
  defp run(min_id) do
    case fetch_batch(min_id) do
      [] ->
        :ok

      revisions ->
        Enum.each(revisions, &migrate_revision/1)
        revisions |> Enum.map(& &1.id) |> Enum.max() |> run()
    end
  end

  @spec fetch_batch(non_neg_integer()) :: [FlowRevision.t()]
  defp fetch_batch(min_id) do
    pattern = Enum.map_join(Map.keys(@deprecated_webhooks), "|", &Regex.escape/1)

    query =
      from(fr in FlowRevision,
        where: fr.id > ^min_id,
        where: fr.status in ["draft", "published"],
        where: fragment("?::text ~ ?", fr.definition, ^pattern),
        order_by: [asc: fr.id],
        limit: ^@batch_size
      )

    Repo.all(query, skip_organization_id: true)
  end

  @spec migrate_revision(FlowRevision.t()) :: :ok
  defp migrate_revision(%FlowRevision{} = flow_revision) do
    {definition, changed?} = migrate_definition(flow_revision.definition)

    if changed? do
      flow_revision
      |> Ecto.Changeset.change(definition: definition)
      |> Repo.update(skip_organization_id: true)
      |> case do
        {:ok, _} ->
          maybe_warn_dangling_translation(flow_revision.id, definition)

        {:error, changeset} ->
          Glific.log_error(
            "Failed to backfill deprecated Bhashini webhook on flow_revision #{flow_revision.id}: #{Glific.SafeLog.safe_inspect(changeset.errors)}"
          )
      end
    end

    :ok
  end

  @doc """
  Pure transform: rewrites every deprecated-webhook `call_webhook` action in a
  flow definition and the downstream result-field references it can safely
  infer. Returns `{definition, changed?}` so callers (and tests) can tell
  whether anything needed fixing.
  """
  @spec migrate_definition(map()) :: {map(), boolean()}
  def migrate_definition(definition) when is_map(definition) do
    {definition, rewrites} = rewrite_call_webhook_actions(definition)

    if rewrites == [],
      do: {definition, false},
      else: {deep_rewrite_result_references(definition, rewrites), true}
  end

  @spec rewrite_call_webhook_actions(map()) :: {map(), [{String.t() | nil, :stt | :tts}]}
  defp rewrite_call_webhook_actions(%{"nodes" => nodes} = definition) do
    {new_nodes, rewrites} =
      Enum.map_reduce(nodes, [], fn node, acc ->
        {new_actions, acc} =
          node
          |> Map.get("actions", [])
          |> Enum.map_reduce(acc, &rewrite_action/2)

        {Map.put(node, "actions", new_actions), acc}
      end)

    {Map.put(definition, "nodes", new_nodes), rewrites}
  end

  defp rewrite_call_webhook_actions(definition), do: {definition, []}

  @spec rewrite_action(map(), list()) :: {map(), list()}
  defp rewrite_action(%{"type" => "call_webhook", "url" => url} = action, acc)
       when is_map_key(@deprecated_webhooks, url) do
    {new_url, family} = Map.fetch!(@deprecated_webhooks, url)

    new_action =
      action
      |> Map.put("url", new_url)
      |> Map.update("body", nil, &rewrite_body(&1, family))

    {new_action, [{action["result_name"], family} | acc]}
  end

  defp rewrite_action(action, acc), do: {action, acc}

  @spec rewrite_body(String.t() | nil, :stt | :tts) :: String.t() | nil
  defp rewrite_body(body, family) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) ->
        decoded
        |> Map.drop(legacy_body_keys(family))
        |> Jason.encode!()

      _ ->
        # Not valid JSON (already-broken custom body) — leave untouched rather
        # than risk corrupting it. The url rewrite alone is enough to clear
        # the "Critical" publish error.
        body
    end
  end

  defp rewrite_body(body, _family), do: body

  @spec legacy_body_keys(:stt | :tts) :: [String.t()]
  defp legacy_body_keys(:stt), do: @stt_legacy_body_keys
  defp legacy_body_keys(:tts), do: @tts_legacy_body_keys

  # Walks every string leaf in the (already url/body-fixed) definition and
  # rewrites the downstream result-field references we can safely infer.
  @spec deep_rewrite_result_references(term(), [{String.t() | nil, :stt | :tts}]) :: term()
  defp deep_rewrite_result_references(term, rewrites) do
    replacements = Enum.flat_map(rewrites, &field_replacements/1)
    deep_map(term, &apply_replacements(&1, replacements))
  end

  @spec field_replacements({String.t() | nil, :stt | :tts}) :: [{String.t(), String.t()}]
  defp field_replacements({nil, _family}), do: []

  defp field_replacements({result_name, :stt}),
    do: [{"#{result_name}.asr_response_text", "#{result_name}.message"}]

  defp field_replacements({result_name, :tts}),
    do: [{"#{result_name}.media_url", "#{result_name}.message"}]

  @spec apply_replacements(String.t(), [{String.t(), String.t()}]) :: String.t()
  defp apply_replacements(string, replacements) do
    Enum.reduce(replacements, string, fn {pattern, replacement}, acc ->
      String.replace(acc, pattern, replacement)
    end)
  end

  @spec deep_map(term(), (String.t() -> String.t())) :: term()
  defp deep_map(map, fun) when is_map(map),
    do: Map.new(map, fn {k, v} -> {k, deep_map(v, fun)} end)

  defp deep_map(list, fun) when is_list(list),
    do: Enum.map(list, &deep_map(&1, fun))

  defp deep_map(string, fun) when is_binary(string), do: fun.(string)

  defp deep_map(other, _fun), do: other

  # The new text_to_speech node has no translation step, so a dangling
  # `.translated_text` reference has no safe automatic replacement (see
  # moduledoc). Surface it so the organization knows to review the flow.
  @spec maybe_warn_dangling_translation(non_neg_integer(), map()) :: :ok
  defp maybe_warn_dangling_translation(flow_revision_id, definition) do
    if definition |> Jason.encode!() |> String.contains?(".translated_text") do
      Glific.log_error(
        "flow_revision #{flow_revision_id}: dangling '.translated_text' reference after " <>
          "Bhashini webhook backfill — the new text_to_speech node has no translation step; " <>
          "review this flow manually.",
        false
      )
    end

    :ok
  end
end
