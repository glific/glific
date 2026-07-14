defmodule Glific.Flows.Webhooks.Kaapi do
  @moduledoc """
  Shared Kaapi helpers for the async Kaapi webhook implementations
  (`speech_to_text`, `text_to_speech`, `filesearch-gpt`, `voice-filesearch-gpt`).

  This module owns the Kaapi-specific plumbing that used to live in
  `Glific.Clients.CommonWebhook`: building the flow-resume callback URL +
  signed `request_metadata`, looking up an assistant's Kaapi config, and
  dispatching the unified LLM call. The per-webhook modules under
  `Glific.Flows.Webhooks.*` call into here from their `call/2` (worker phase).
  """

  alias Glific.Assistants.Assistant
  alias Glific.Flows.Webhooks.ErrorType
  alias Glific.Partners
  alias Glific.Repo
  alias Glific.SafeLog
  alias Glific.ThirdParty.Kaapi
  alias Glific.ThirdParty.Kaapi.ApiClient

  require Logger

  # Shared per-org rate limit for Kaapi STT/TTS dispatch (lifted from the former SttTtsWorker):
  # STT and TTS share ONE per-org budget — at most @rate_limit_max dispatches per
  # @rate_limit_window_ms combined — so both nodes call check_rate_limit/1 rather than keeping
  # independent limiters (two buckets would double the effective limit).
  @rate_limit_window_ms 60_000
  @rate_limit_max 10
  @rate_limit_snooze_seconds 5

  @doc """
  Check-and-consume the shared STT/TTS budget for `organization_id`.

  `ExRated.check_rate/3` both checks and consumes a token: under the limit it returns `:ok` and
  reserves this job's slot; over the limit it returns `{:snooze, seconds}` so the Oban worker
  reschedules instead of hammering Kaapi.
  """
  @spec check_rate_limit(non_neg_integer()) :: :ok | {:snooze, pos_integer()}
  def check_rate_limit(organization_id) do
    key = "kaapi_stt_tts:#{Partners.organization(organization_id).shortcode}"

    case ExRated.check_rate(key, @rate_limit_window_ms, @rate_limit_max) do
      {:ok, _count} -> :ok
      {:error, _limit} -> {:snooze, @rate_limit_snooze_seconds}
    end
  end

  @doc """
  Builds the callback URL and signed `request_metadata` map for a Kaapi async call.

  Centralises signature generation and callback-URL construction shared by STT, TTS,
  and the unified LLM calls. `callback_path` defaults to the standard flow-resume route;
  the voice LLM path passes `"/kaapi/voice_flow_resume"`. `timestamp` may be supplied to
  keep latency measurement consistent across a multi-step call.
  """
  @spec build_flow_resume_metadata(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          map(),
          String.t(),
          integer() | nil
        ) :: {String.t(), map()}
  def build_flow_resume_metadata(
        organization_id,
        flow_id,
        contact_id,
        fields,
        callback_path \\ "/webhook/flow_resume",
        timestamp \\ nil
      ) do
    timestamp = timestamp || DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    signature_payload = %{
      "organization_id" => organization_id,
      "flow_id" => flow_id,
      "contact_id" => contact_id,
      "timestamp" => timestamp
    }

    signature =
      Glific.signature(
        organization_id,
        Jason.encode!(signature_payload),
        timestamp
      )

    organization = Partners.organization(organization_id)

    callback_url = Glific.api_callback_base(organization.shortcode) <> callback_path

    request_metadata = %{
      organization_id: organization_id,
      flow_id: flow_id,
      contact_id: contact_id,
      timestamp: timestamp,
      signature: signature,
      webhook_log_id: fields["webhook_log_id"],
      result_name: fields["result_name"]
    }

    {callback_url, request_metadata}
  end

  @doc """
  Dispatches the async unified LLM call to Kaapi (`/api/v1/llm/call`).

  Expects the org Kaapi API key in `headers` as `X-API-KEY`. On success returns the
  normalised Kaapi ack body (`%{success: true, ...}`); Kaapi POSTs the actual result to
  the flow-resume callback later. On failure returns `%{success: false, reason: ...}`.
  """
  @spec call_llm(map(), list(), String.t(), map()) :: map()
  def call_llm(fields, headers, callback_url, request_metadata) do
    {_, org_api_key} = Enum.find(headers, {nil, nil}, fn {key, _v} -> key == "X-API-KEY" end)
    {:ok, organization_id} = fields["organization_id"] |> Glific.parse_maybe_integer()

    with {:ok, {kaapi_uuid, version_number}} <-
           lookup_kaapi_config(fields["assistant_id"], organization_id),
         payload =
           build_unified_llm_payload(
             fields,
             kaapi_uuid,
             version_number,
             callback_url,
             request_metadata
           ),
         {:ok, body} <- ApiClient.call_llm(payload, org_api_key) do
      Kaapi.normalize_kaapi_body(body)
    else
      {:error, error_type, reason} when is_atom(error_type) ->
        %{success: false, reason: reason, error_type: error_type}

      {:error, %{status: status, body: body}} ->
        %{success: false, reason: Jason.encode!(body), http_status: status, error_type: :unknown}

      {:error, reason} when is_binary(reason) ->
        %{success: false, reason: reason, error_type: :unknown}

      {:error, reason} ->
        %{success: false, reason: SafeLog.safe_inspect(reason), error_type: :unknown}
    end
  end

  @doc """
  Parses `{organization_id, flow_id, contact_id}` from a webhook fields map. All three
  are required (the Kaapi callback signature depends on them). Returns a tagged tuple so
  callers route a malformed payload to the Failure branch rather than crashing the worker;
  the error string intentionally omits the payload to avoid leaking user data into logs.
  """
  @spec parse_flow_fields(map()) ::
          {:ok, {non_neg_integer(), non_neg_integer(), non_neg_integer()}}
          | {:error, ErrorType.t(), String.t()}
  def parse_flow_fields(fields) do
    with {:ok, organization_id} <- Glific.parse_maybe_integer(fields["organization_id"]),
         {:ok, flow_id} <- Glific.parse_maybe_integer(fields["flow_id"]),
         {:ok, contact_id} <- Glific.parse_maybe_integer(fields["contact_id"]) do
      {:ok, {organization_id, flow_id, contact_id}}
    else
      _ -> {:error, :invalid_input, "Invalid or missing flow metadata for Kaapi webhook"}
    end
  end

  @doc """
  Validates that a media URL is a well-formed https URL. Used by the STT webhook
  before dispatching to Kaapi.
  """
  @spec validate_media(any()) :: :ok | {:error, ErrorType.t(), String.t()}
  def validate_media(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
        :ok

      _ ->
        {:error, :invalid_media_url, "Media URL is invalid"}
    end
  end

  def validate_media(_), do: {:error, :invalid_media_url, "Media URL is needed"}

  # An unresolvable assistant is a flow-author/config mistake (bad or unset assistant id) → config.
  @spec lookup_kaapi_config(String.t() | nil, non_neg_integer()) ::
          {:ok, {String.t(), non_neg_integer()}} | {:error, ErrorType.t(), String.t()}
  defp lookup_kaapi_config(assistant_display_id, _organization_id)
       when is_nil(assistant_display_id),
       do: {:error, :invalid_input, "assistant_id is required"}

  defp lookup_kaapi_config(assistant_display_id, organization_id) do
    with {:ok, assistant} <-
           Repo.fetch_by(Assistant, %{
             assistant_display_id: assistant_display_id,
             organization_id: organization_id
           }),
         assistant <- Repo.preload(assistant, :active_config_version),
         {:ok, kaapi_uuid} <- fetch_kaapi_uuid(assistant),
         %{kaapi_version_number: kaapi_version_number} when not is_nil(kaapi_version_number) <-
           assistant.active_config_version do
      {:ok, {kaapi_uuid, kaapi_version_number}}
    else
      {:error, :missing_kaapi_uuid} ->
        {:error, :invalid_input, "Assistant is still being set up"}

      {:error, _} ->
        {:error, :invalid_input, "Assistant not found: #{assistant_display_id}"}

      nil ->
        {:error, :invalid_input,
         "No active config version found for assistant #{assistant_display_id}"}

      %{kaapi_version_number: nil} ->
        {:error, :invalid_input, "Kaapi version number not found"}
    end
  end

  @spec fetch_kaapi_uuid(map()) :: {:ok, String.t()} | {:error, :missing_kaapi_uuid}
  defp fetch_kaapi_uuid(%{kaapi_uuid: nil}), do: {:error, :missing_kaapi_uuid}
  defp fetch_kaapi_uuid(%{kaapi_uuid: uuid}), do: {:ok, uuid}

  @spec build_unified_llm_payload(map(), String.t(), non_neg_integer(), String.t(), map()) ::
          map()
  defp build_unified_llm_payload(
         fields,
         kaapi_uuid,
         version_number,
         callback_url,
         request_metadata
       ) do
    %{
      query: %{
        input: fields["question"],
        conversation: build_conversation(fields["thread_id"])
      },
      config: %{
        id: kaapi_uuid,
        version: version_number
      },
      callback_url: callback_url,
      request_metadata: request_metadata
    }
  end

  @spec build_conversation(String.t() | nil) :: map()
  defp build_conversation(nil), do: %{auto_create: true}
  defp build_conversation(thread_id), do: %{id: thread_id}
end
