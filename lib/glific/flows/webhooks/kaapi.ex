defmodule Glific.Flows.Webhooks.Kaapi do
  @moduledoc """
  Shared Kaapi helpers for the async Kaapi webhook implementations (STT, TTS, filesearch-gpt,
  voice-filesearch-gpt): callback URL/signed metadata, config lookup, and the unified LLM call.
  """

  alias Glific.Assistants.Assistant
  alias Glific.Flows.Webhooks.ErrorType
  alias Glific.Partners
  alias Glific.Repo
  alias Glific.SafeLog
  alias Glific.ThirdParty.Kaapi
  alias Glific.ThirdParty.Kaapi.ApiClient

  require Logger

  # STT and TTS share ONE per-org rate-limit budget (not independent buckets, which would
  # double the effective limit).
  @rate_limit_window_ms 60_000
  @rate_limit_max 10
  @rate_limit_snooze_seconds 5

  @doc "Check-and-consume the shared STT/TTS rate-limit budget for `organization_id`."
  @spec check_rate_limit(non_neg_integer()) :: :ok | {:snooze, pos_integer()}
  def check_rate_limit(organization_id) do
    key = "kaapi_stt_tts:#{Partners.organization(organization_id).shortcode}"

    case ExRated.check_rate(key, @rate_limit_window_ms, @rate_limit_max) do
      {:ok, _count} -> :ok
      {:error, _limit} -> {:snooze, @rate_limit_snooze_seconds}
    end
  end

  @doc "Builds the callback URL and signed `request_metadata` map for a Kaapi async call."
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
  Dispatches the async unified LLM call to Kaapi (`/api/v1/llm/call`). Returns the normalised
  ack body on success; Kaapi POSTs the actual result to the flow-resume callback later.
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

  # Upstream busy/overloaded/rate-limited → :service_unavailable (system), not config. Kept
  # specific — a bare "try again" also appears in plenty of 4xx config errors.
  @overloaded ~r/conversation_locked|Another process is currently operating|is overloaded|server_is_overloaded|rate limit/i

  @code ~r/\(code:\s*(\d{3})|Status:\s*(\d{3})/

  @doc """
  Classifies a failed async Kaapi callback into an `ErrorType.t()`: overloaded/locked upstream
  → `:service_unavailable`; otherwise the status is bucketed by `from_http_status/1`.
  """
  @spec classify(map()) :: ErrorType.t()
  def classify(result) when is_map(result) do
    reason = to_reason(result)
    code = to_status(result["http_status"]) || provider_status(reason)

    if reason =~ @overloaded do
      :service_unavailable
    else
      from_http_status(code)
    end
  end

  def classify(_result), do: :unknown

  @doc """
  Maps a raw HTTP status to an `ErrorType.t()`, so every webhook failure buckets a status the
  same way: 429 → `:rate_limited`, 408 → `:service_unavailable`, other 4xx → `:invalid_input`,
  everything else (5xx, transport atoms, nil) → `:unknown`. Lives here rather than in
  `ErrorType` because it *decides* a type, whereas `ErrorType` only defines the vocabulary.
  """
  @spec from_http_status(any()) :: ErrorType.t()
  def from_http_status(429), do: :rate_limited
  def from_http_status(408), do: :service_unavailable
  def from_http_status(status) when is_integer(status) and status in 400..499, do: :invalid_input
  def from_http_status(_status), do: :unknown

  # Status may arrive as an integer or a JSON string ("404"); anything else → nil.
  @spec to_status(any()) :: integer() | nil
  defp to_status(status) when is_integer(status), do: status

  defp to_status(status) when is_binary(status) do
    # Only a cleanly-parsed integer counts — Integer.parse/1 accepts prefixes ("404invalid" -> 404).
    case status |> String.trim() |> Integer.parse() do
      {code, ""} -> code
      _ -> nil
    end
  end

  defp to_status(_status), do: nil

  # The reason lives under "reason" or (some failures) "error"; absent/non-binary → "".
  @spec to_reason(map()) :: String.t()
  defp to_reason(%{"reason" => reason}) when is_binary(reason), do: reason
  defp to_reason(%{"error" => error}) when is_binary(error), do: error
  defp to_reason(_result), do: ""

  @spec provider_status(String.t()) :: integer() | nil
  defp provider_status(reason) do
    case Regex.run(@code, reason) do
      [_, code] -> String.to_integer(code)
      [_, _, code] -> String.to_integer(code)
      _ -> nil
    end
  end

  @doc """
  Converts a Kaapi ack map into the typed `call/2` result: success parks the flow (`{:ok, ack}`);
  failure becomes `{:error, type, reason}`, folding `http_status` into the reason.
  """
  @spec to_result(map()) :: {:ok, map()} | {:error, ErrorType.t(), String.t()}
  def to_result(%{success: true} = ack), do: {:ok, ack}

  def to_result(%{success: false} = ack) do
    {:error, ack_error_type(ack[:error_type]), ack_reason(ack)}
  end

  @spec ack_error_type(any()) :: ErrorType.t()
  defp ack_error_type(error_type) when is_atom(error_type) do
    if ErrorType.class(error_type), do: error_type, else: :unknown
  end

  defp ack_error_type(_error_type), do: :unknown

  @spec ack_reason(map()) :: String.t()
  defp ack_reason(ack) do
    reason = ack[:reason] || ack[:error] || "Kaapi dispatch failure"
    reason = if is_binary(reason), do: reason, else: SafeLog.safe_inspect(reason)

    case ack[:http_status] do
      status when is_integer(status) -> "#{reason} (HTTP #{status})"
      _ -> reason
    end
  end

  @doc """
  Parses `{organization_id, flow_id, contact_id}` from a webhook fields map. Returns a tagged
  tuple so callers route a malformed payload to Failure instead of crashing the worker; the
  error string omits the payload to avoid leaking user data into logs.
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

  @doc "Validates that a media URL is a well-formed https URL."
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

  # An unresolvable assistant is a flow-author/config mistake → config.
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
