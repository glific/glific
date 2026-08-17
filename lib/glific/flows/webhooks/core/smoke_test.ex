defmodule Glific.Flows.Webhooks.Core.SmokeTest do
  @moduledoc """
  Active uptime probe for the flow-webhook nodes. Calls each of the five current implementations'
  `call/2` with fixture input against a sandbox/staging org and reports whether the node's external
  dependencies are alive. This complements — it does not replace — the passive per-node alerting on
  the `"flow_webhook_count"` AppSignal distribution:

    * this probe catches "dependency down but no live traffic" (a silent outage),
    * the `"flow_webhook_count"` alerts catch elevated error rates in real traffic.

  Async nodes (STT, TTS, filesearch-gpt, voice-filesearch-gpt) dispatch to Kaapi and return
  `{:ok, ack}` once the request is accepted; the callback that Kaapi POSTs back carries a
  `smoke_test` sentinel so the flow-resume path drops it before it counts against
  `"flow_webhook_count"` (see `Glific.Flows.Webhooks.Kaapi.build_flow_resume_metadata/6` and
  `Glific.Flows.Webhook.resume/4`). So a probe run never pollutes the production metric.

  ## Running

  From a `mix` shell / CI against a staging DB:

      mix glific.webhooks.smoke_test --org 1

  From a Gigalixir `remote_console` against the running staging app:

      Glific.Flows.Webhooks.Core.SmokeTest.run_all(1)
      Glific.Flows.Webhooks.Core.SmokeTest.run_all(1, %{assistant_id: "asst_123", audio_url: "https://.../sample.ogg"})

  ## Fixtures

  `geolocation` uses static coordinates. The async nodes need org-specific fixtures — a reachable
  `audio_url`, a configured `assistant_id`, and a `flow_id`/`contact_id` to sign the callback with.
  Supply them via the `overrides` map or `config :glific, #{inspect(__MODULE__)}, ...`; a node whose
  fixture is missing surfaces the node's own typed error rather than crashing the run.

  ## Alerting (ops-side)

  The `"flow_webhook_count"` distribution is already tagged `%{webhook_name, status}`. Configure a
  per-`webhook_name` AppSignal trigger that alerts when
  `sum(status: "failure") / sum(all) > X%` over an N-minute window (X TBD with ops). No code change
  is needed — the metric dimensions already exist.
  """

  alias Glific.Flows.Webhooks.{
    FilesearchGpt,
    Geolocation,
    SpeechToText,
    TextToSpeech,
    VoiceFilesearchGpt
  }

  alias Glific.Repo
  alias Glific.SafeLog

  # Ordered so the printed summary reads sync-first, then the Kaapi async nodes.
  @webhooks [
    {"geolocation", Geolocation},
    {"speech_to_text", SpeechToText},
    {"text_to_speech", TextToSpeech},
    {"filesearch-gpt", FilesearchGpt},
    {"voice-filesearch-gpt", VoiceFilesearchGpt}
  ]

  # Bengaluru — a stable coordinate that reverse-geocodes to a real address.
  @default_lat "12.9716"
  @default_long "77.5946"
  @default_text "Glific webhook smoke test."
  @default_question "What is Glific?"
  @default_source_language "english"
  @default_target_language "english"

  @type outcome :: :ok | {:error, term()}

  @doc """
  Run every flow-webhook smoke check for `org_id`, returning `%{node_name => :ok | {:error, reason}}`.

  `overrides` (atom-keyed) supplies the org-specific fixtures — `:assistant_id`, `:audio_url`,
  `:flow_id`, `:contact_id`, and optionally `:lat`/`:long`/`:text`/`:question`/`:source_language`/
  `:target_language` — falling back to `config :glific, #{inspect(__MODULE__)}` and then to defaults.
  """
  @spec run_all(non_neg_integer(), map()) :: %{String.t() => outcome()}
  def run_all(org_id, overrides \\ %{}) when is_integer(org_id) do
    Repo.put_organization_id(org_id)
    config = build_config(org_id, overrides)
    ctx = %{organization_id: org_id}

    results =
      Map.new(@webhooks, fn {name, module} ->
        {name, run_one(module, fixtures(name, config), ctx)}
      end)

    print_summary(org_id, results)
    results
  end

  @spec run_one(module(), map(), map()) :: outcome()
  defp run_one(module, fields, ctx) do
    case module.call(fields, ctx) do
      {:ok, _value} -> :ok
      {:error, _type, reason} -> {:error, reason}
      {:snooze, seconds} -> {:error, "snoozed (#{seconds}s) — rate limited or transient"}
      other -> {:error, SafeLog.safe_inspect(other)}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  @spec fixtures(String.t(), map()) :: map()
  defp fixtures("geolocation", config), do: %{"lat" => config.lat, "long" => config.long}

  defp fixtures("speech_to_text", config),
    do: Map.put(flow_fields(config), "speech", config.audio_url)

  defp fixtures("text_to_speech", config),
    do: Map.put(flow_fields(config), "text", config.text)

  defp fixtures("filesearch-gpt", config) do
    Map.merge(flow_fields(config), %{
      "assistant_id" => config.assistant_id,
      "question" => config.question
    })
  end

  defp fixtures("voice-filesearch-gpt", config) do
    Map.merge(flow_fields(config), %{
      "speech" => config.audio_url,
      "assistant_id" => config.assistant_id,
      "question" => config.question,
      "source_language" => config.source_language,
      "target_language" => config.target_language
    })
  end

  # Mirrors a real flow-webhook payload: string keys, ids as strings. The `smoke_test` sentinel
  # rides through to the Kaapi callback so it is dropped before counting.
  @spec flow_fields(map()) :: map()
  defp flow_fields(config) do
    %{
      "organization_id" => to_string(config.org_id),
      "flow_id" => to_string(config.flow_id),
      "contact_id" => to_string(config.contact_id),
      "smoke_test" => true
    }
  end

  @spec build_config(non_neg_integer(), map()) :: map()
  defp build_config(org_id, overrides) do
    env = Application.get_env(:glific, __MODULE__, [])

    %{
      org_id: org_id,
      lat: fetch(overrides, env, :lat, @default_lat),
      long: fetch(overrides, env, :long, @default_long),
      text: fetch(overrides, env, :text, @default_text),
      question: fetch(overrides, env, :question, @default_question),
      source_language: fetch(overrides, env, :source_language, @default_source_language),
      target_language: fetch(overrides, env, :target_language, @default_target_language),
      audio_url: fetch(overrides, env, :audio_url, nil),
      assistant_id: fetch(overrides, env, :assistant_id, nil),
      flow_id: fetch(overrides, env, :flow_id, nil),
      contact_id: fetch(overrides, env, :contact_id, nil)
    }
  end

  @spec fetch(map(), keyword(), atom(), term()) :: term()
  defp fetch(overrides, env, key, default),
    do: Map.get(overrides, key) || Keyword.get(env, key) || default

  @spec print_summary(non_neg_integer(), %{String.t() => outcome()}) :: :ok
  defp print_summary(org_id, results) do
    IO.puts("\nFlow-webhook smoke test  org_id=#{org_id}")

    Enum.each(@webhooks, fn {name, _module} ->
      case Map.fetch!(results, name) do
        :ok -> IO.puts("  ✓ #{name}")
        {:error, reason} -> IO.puts("  ✗ #{name}  —  #{reason}")
      end
    end)

    :ok
  end
end
