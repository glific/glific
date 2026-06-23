defmodule Glific.Flows.Webhook do
  @moduledoc """
  Lets wrap all webhook functionality here as we try and get
  a better handle on the breadth and depth of webhooks.
  """
  use Gettext, backend: GlificWeb.Gettext
  require Logger

  alias Glific.{
    Contacts.Contact,
    GCS.GcsWorker,
    Messages,
    Partners,
    Repo
  }

  alias Glific.Flows.{Action, FlowContext, WebhookLog}

  alias Glific.Flows.Webhooks.{
    Dispatcher,
    Instrumentation,
    Registry,
    Support,
    VoiceFilesearchGpt
  }

  # Per-org rate limit for Kaapi STT/TTS dispatch (lifted from the former SttTtsWorker):
  # at most @rate_limit_max requests per org within @rate_limit_window_ms; over-limit jobs
  # snooze rather than hammer Kaapi.
  @rate_limited_urls ["speech_to_text", "text_to_speech"]
  @rate_limit_window_ms 60_000
  @rate_limit_max 10
  @rate_limit_snooze_seconds 5

  use Oban.Worker,
    queue: :webhook,
    max_attempts: 2,
    priority: 0,
    unique: [
      period: 60,
      fields: [:args, :worker],
      keys: [:context_id, :url, :action_id],
      states: [:available, :scheduled, :executing, :completed]
    ]

  defmodule Error do
    @moduledoc """
    Custom error module for Kaapi webhook failures.
    Since Kaapi is a backend service (NGOs don’t interact with it directly),
    sending errors to them won’t resolve the issue.
    Reporting these failures to AppSignal lets us detect and fix problems
    """
    defexception [:message, :reason, :organization_id]
  end

  defmodule SystemError do
    @moduledoc """
    Webhook failure: 4xx/5xx HTTP responses, transport errors (DNS,
    connection refused, timeout), unexpected response shapes. Keep the
    `:message` field low-cardinality so AppSignal groups identical failures
    into one incident; per-occurrence detail (org, status, reason) is
    attached as AppSignal tags via `Span.set_sample_data` at the report
    site, not on the struct.
    """
    defexception [:message]
  end

  defmodule TimeoutError do
    @moduledoc """
    Webhook timeout: an async webhook (STT/TTS/unified-llm) parked the flow
    waiting for a Kaapi callback, but none arrived within the wait window.
    A distinct exception module so AppSignal groups timeouts into their own
    incident, separate from `SystemError`.
    """
    defexception [:message]
  end

  @non_unique_urls [
    "parse_via_gpt_vision",
    "parse_via_chat_gpt",
    "filesearch-gpt",
    "voice-filesearch-gpt",
    "speech_to_text",
    "text_to_speech",
    "speech_to_text_with_bhasini",
    "nmt_tts_with_bhasini"
  ]

  @doc """
  Report a flow-webhook exception (`SystemError` / `Timeout`) to AppSignal
  under the `flow_webhooks` namespace.
  """
  @spec report_to_appsignal(Exception.t(), map()) :: :ok
  def report_to_appsignal(exception, tags) when is_map(tags) do
    Logger.error(Exception.message(exception))

    Appsignal.send_error(exception, [], fn span ->
      span
      |> Appsignal.Span.set_namespace("flow_webhooks")
      |> Appsignal.Span.set_sample_data("tags", tags)
    end)

    :ok
  end

  @doc """
  Increment a counter for a flow-webhook node outcome so success/failure ratios
  can be computed per webhook node. `status` is "success" or "failure".
  """
  @spec track_webhook_count(String.t() | nil, String.t()) :: :ok
  def track_webhook_count(webhook_name, status) do
    Appsignal.increment_counter("flow_webhook_count", 1, %{
      webhook_name: webhook_name || "unknown",
      status: status
    })

    :ok
  end

  @doc """
  Records end-to-end latency for a webhook node execution as an AppSignal
  distribution (so p50/p95/p99 can be charted). Generic across all node types
  """
  @spec track_webhook_latency(String.t() | nil, String.t(), number()) :: :ok
  def track_webhook_latency(webhook_name, status, duration_ms) do
    Appsignal.add_distribution_value("flow_webhook_latency", duration_ms, %{
      webhook_name: webhook_name || "unknown",
      status: status
    })

    :ok
  end

  @doc """
  Execute a webhook action, could be either get or post for now
  """
  @spec execute(Action.t(), FlowContext.t()) :: nil
  def execute(action, context) do
    Glific.Metrics.increment("Webhook", context.organization_id)

    case String.downcase(action.method) do
      "get" -> method(action, context)
      "post" -> method(action, context)
      "function" -> method(action, context)
    end

    nil
  end

  @doc """
  Update a webhook log with the given message.
  """
  @spec update_log(WebhookLog.t() | non_neg_integer, map() | binary()) ::
          {:ok, WebhookLog.t()} | {:error, Ecto.Changeset.t()}
  def update_log(webhook_log_id, message) when is_integer(webhook_log_id) do
    webhook_log = Repo.get!(WebhookLog, webhook_log_id)
    update_log(webhook_log, message)
  end

  def update_log(webhook_log, %{body: body} = message) when is_map(message) and body != nil do
    # handle incorrect json body
    json_body =
      case Jason.decode(body) do
        {:ok, json_body} ->
          json_body

        _ ->
          nil
      end

    attrs = %{
      response_json: json_body,
      status_code: message.status
    }

    webhook_log |> WebhookLog.update_webhook_log(attrs)
  end

  # Distinguishes a success map from an application-level failure map
  # (%{success: false, ...}) so the WebhookLog row records the failure with a
  # non-200 status and an error reason
  def update_log(webhook_log, %{success: false} = result) do
    reason =
      Map.get(result, :reason) || Map.get(result, :error) || Map.get(result, :message)

    # reason can be a non-binary term (e.g. a decoded JSON map from a Tesla 500
    # body — see lib/glific/third_party/bhasini/bhasini.ex). to_string/1 would
    # raise on those; inspect/1 produces a safe string for any term.
    error =
      cond do
        is_binary(reason) -> reason
        is_nil(reason) -> "Webhook failure"
        true -> inspect(reason)
      end

    attrs = %{response_json: result, status_code: 400, error: error}

    webhook_log
    |> WebhookLog.update_webhook_log(attrs)
  end

  def update_log(webhook_log, result) when is_map(result) do
    attrs = %{response_json: result, status_code: 200}

    webhook_log
    |> WebhookLog.update_webhook_log(attrs)
  end

  def update_log(webhook_log, error_message) do
    attrs = %{
      error: error_message,
      status_code: 400
    }

    webhook_log
    |> WebhookLog.update_webhook_log(attrs)
  end

  # method can be either a get or a post. The do_oban function
  # does the right thing based on if it is a get or post
  @spec method(Action.t(), FlowContext.t()) :: nil
  defp method(action, context) do
    case Support.create_body(context, action.body) do
      {:error, message} ->
        action
        |> Support.create_log(%{}, action.headers, context)
        |> update_log(message)

      {map, body} ->
        do_oban(action, context, {map, body})
    end

    nil
  end

  @spec do_oban(Action.t(), FlowContext.t(), tuple()) :: any
  defp do_oban(action, context, {map, body}) do
    parsed_attrs = Support.parse_header_and_url(action, context)

    headers = Support.add_signature(parsed_attrs.header, context.organization_id, body)
    action = Map.put(action, :url, parsed_attrs.url)
    webhook_log = Support.create_log(action, map, parsed_attrs.header, context)

    payload =
      %{
        method: String.downcase(action.method),
        url: parsed_attrs.url,
        result_name: action.result_name,
        body: body,
        headers: headers,
        webhook_log_id: webhook_log.id,
        flow_id: context.flow_id,
        contact_id: context.contact_id,
        # for job uniqueness,
        context_id: context.id,
        context: %{id: context.id, delay: context.delay, uuids_seen: context.uuids_seen},
        organization_id: context.organization_id,
        action_id: action.uuid
      }

    create_oban_changeset(payload)
    |> Oban.insert()
    |> case do
      {:ok, %Job{conflict?: true} = response} ->
        error =
          "Message received while executing webhook. context: #{context.id} and url: #{parsed_attrs.url}"

        Glific.log_error(error, false)

        {:ok, response}

      {:ok, response} ->
        {:ok, response}

      response ->
        Glific.log_error(
          "something wrong while inserting webhook node. ",
          true
        )

        response
    end
  end

  @spec do_action(String.t(), String.t(), map() | String.t(), list()) :: any
  defp do_action("post", url, body, headers),
    do: Tesla.post(url, body, headers: headers)

  defp do_action("get", url, body, headers),
    do:
      Tesla.get(url,
        headers: headers,
        query: Enum.into(Jason.decode!(body), []),
        opts: [adapter: [recv_timeout: 10_000]]
      )

  defp do_action("function", function, fields, headers) do
    {
      :ok,
      :function,
      dispatch_function(function, fields, headers)
    }
  rescue
    error ->
      # Report via the centralized wrapper (not Appsignal directly). The webhook name is
      # safe to log; the request payload is omitted to avoid leaking user data.
      Glific.log_exception(error)
      {:error, "Calling webhook function #{inspect(function)} threw: #{Exception.message(error)}"}
  end

  # Routes a function-type webhook to the central Dispatcher when it is registered (sync or
  # async — both run their module's call/2 wrapped in instrumentation), otherwise falls back
  # to the legacy Glific.Clients.webhook chain (CommonWebhook + per-org client modules).
  @spec dispatch_function(String.t(), map(), list()) :: any()
  defp dispatch_function(function, fields, headers) do
    case Registry.lookup(function) do
      module when not is_nil(module) and is_atom(module) ->
        Dispatcher.dispatch(function, fields, headers)

      _ ->
        Glific.Clients.webhook(function, fields, headers)
    end
  end

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, String.t()} | {:snooze, pos_integer()}
  def perform(
        %Oban.Job{
          args:
            %{
              "method" => method,
              "url" => url,
              "result_name" => result_name,
              "body" => body,
              "headers" => headers,
              "webhook_log_id" => webhook_log_id,
              "context" => context,
              "organization_id" => organization_id
            } = args
        } = _job
      ) do
    Repo.put_process_state(organization_id)

    if rate_limited?(url, organization_id) do
      {:snooze, @rate_limit_snooze_seconds}
    else
      headers = Enum.reduce(headers, [], fn {k, v}, acc -> acc ++ [{k, v}] end)

      # Function webhooks receive the decoded body enriched with the flow metadata the
      # registered modules need (flow/contact ids, webhook_log_id, result_name). POST/GET
      # keep the raw body string they send to the external service.
      enrichment = %{
        "flow_id" => args["flow_id"],
        "contact_id" => args["contact_id"],
        "webhook_log_id" => webhook_log_id,
        "result_name" => result_name
      }

      result =
        case do_action(method, url, action_input(method, body, enrichment), headers) do
          {:ok, :function, result} ->
            update_log(webhook_log_id, result)
            result

          {:ok, %Tesla.Env{status: status} = message} when status in 200..299 ->
            case Jason.decode(message.body) do
              {:ok, list_response} when is_list(list_response) ->
                list_response = format_response(list_response)
                updated_message = Map.put(message, :body, Jason.encode!(list_response))
                update_log(webhook_log_id, updated_message)
                list_response

              {:ok, json_response} ->
                update_log(webhook_log_id, message)
                format_response(json_response)

              {:error, _error} ->
                update_log(webhook_log_id, "Could not decode message body: " <> message.body)

                nil
            end

          {:ok, %Tesla.Env{} = message} ->
            update_log(webhook_log_id, "Did not return a 200..299 status code" <> message.body)
            nil

          {:error, error_message} ->
            update_log(webhook_log_id, inspect(error_message))
            nil
        end

      handle_webhook_result(result, context, result_name, url, organization_id)
    end
  end

  # Per-org rate limit for Kaapi STT/TTS dispatch. ExRated.check_rate both checks and
  # consumes a token, so a successful check (under limit) reserves this job's slot; an
  # over-limit job is snoozed and retried later. Other webhooks are never rate limited.
  @spec rate_limited?(String.t(), non_neg_integer()) :: boolean()
  defp rate_limited?(url, organization_id) when url in @rate_limited_urls do
    organization = Partners.organization(organization_id)
    key = "kaapi_stt_tts:#{organization.shortcode}"

    case ExRated.check_rate(key, @rate_limit_window_ms, @rate_limit_max) do
      {:ok, _count} -> false
      {:error, _limit} -> true
    end
  end

  defp rate_limited?(_url, _organization_id), do: false

  # Builds the input passed to do_action/4. Function webhooks get the decoded body
  # merged with flow metadata; POST/GET keep the raw body string.
  @spec action_input(String.t(), String.t(), map()) :: map() | String.t()
  defp action_input("function", body, enrichment),
    do: body |> Jason.decode!() |> Map.merge(enrichment)

  defp action_input(_method, body, _enrichment), do: body

  # Routes the dispatch result to the flow engine. For async webhooks a successful ack
  # leaves the flow parked (the Kaapi callback resumes it via FlowResumeController); a
  # failure wakes the flow on the Failure branch. Sync webhooks resume immediately.
  @spec handle_webhook_result(any(), map(), String.t(), String.t(), non_neg_integer()) :: :ok
  defp handle_webhook_result(result, context, result_name, url, organization_id) do
    if Registry.async?(url) do
      case result do
        %{success: true} -> :ok
        _ -> wake_with_failure(context, organization_id)
      end
    else
      handle(result, context, result_name)
    end
  end

  # Wakes a parked flow on the Failure branch (used when an async webhook fails to dispatch).
  @spec wake_with_failure(map(), non_neg_integer()) :: :ok
  defp wake_with_failure(context_data, organization_id) do
    context =
      Repo.get!(FlowContext, context_data["id"])
      |> Repo.preload(:flow)
      |> Map.put(:delay, context_data["delay"] || 0)
      |> Map.put(:uuids_seen, context_data["uuids_seen"])

    message = Messages.create_temp_message(organization_id, "Failure")
    FlowContext.wakeup_one(context, message)
    :ok
  end

  @spec handle(String.t(), map(), String.t()) :: :ok
  defp handle(result, context_data, result_name) do
    context_id = context_data["id"]
    ## In case the context already carries a delay before webhook,
    ## we are going to use that.

    context =
      Repo.get!(FlowContext, context_id)
      |> Repo.preload(:flow)
      |> Map.put(:delay, context_data["delay"] || 0)
      |> Map.put(:uuids_seen, context_data["uuids_seen"])

    {context, message} =
      if is_nil(result) || !is_map(result) || is_nil(result_name) do
        {
          context,
          Messages.create_temp_message(context.organization_id, "Failure")
        }
      else
        # update the context with the results from webhook return values
        {
          FlowContext.update_results(
            context,
            %{result_name => Map.put(result, :inserted_at, DateTime.utc_now())}
          ),
          Messages.create_temp_message(context.organization_id, "Success")
        }
      end

    FlowContext.wakeup_one(context, message)
    :ok
  end

  @spec format_response(any()) :: any()
  defp format_response(response_json) when is_list(response_json) do
    Enum.with_index(response_json)
    |> Enum.map(fn {value, index} ->
      {index, format_response(value)}
    end)
    |> Enum.into(%{})
  end

  defp format_response(response_json) when is_map(response_json) do
    response_json
    |> Enum.map(fn {key, value} -> {key, format_response(value)} end)
    |> Enum.into(%{})
  end

  defp format_response(response_json), do: response_json

  @spec create_oban_changeset(map()) :: Oban.Job.changeset()
  defp create_oban_changeset(%{url: "create_certificate"} = payload) do
    __MODULE__.new(payload,
      queue: :custom_certificate
    )
  end

  defp create_oban_changeset(%{url: url} = payload) when url in @non_unique_urls do
    opts = [
      queue: :gpt_webhook_queue,
      unique: nil
    ]

    # Bhasini tts API is performing badly for a long-time, so keeping the priority low, so other jobs can run
    # But this priorty will be bumped every 5 mins to avoid starvation
    if url == "nmt_tts_with_bhasini" do
      __MODULE__.new(payload, Keyword.merge(opts, priority: 2))
    else
      __MODULE__.new(payload, opts)
    end
  end

  defp create_oban_changeset(payload), do: __MODULE__.new(payload)

  # --------------------------------------------------------------------------
  # Async callback resume — the inbound counterpart of execute/2 + perform/1.
  #
  # `GlificWeb.Flows.FlowResumeController` stays thin: it pulls org context off
  # the connection, parses the callback (`parse_callback_response/1`) and uploads
  # any TTS audio (`maybe_upload_tts_audio/1`) in the request process, then hands
  # off to `resume/3` / `voice_resume/3`. Validation, logging, telemetry and the
  # actual flow resume all live here so the signing (`add_signature/3`) and the
  # verification (`validate_request/2`) sit in one module.
  # --------------------------------------------------------------------------

  @doc """
  Resume a flow parked on an async webhook, from the parsed Kaapi callback.

  Validates the callback signature and contact BEFORE any side effect, then
  updates the webhook log, records telemetry, and resumes the contact's flow
  with the parsed callback merged into the flow results.
  """
  @spec resume(non_neg_integer(), map(), map()) :: :ok
  def resume(organization_id, result, response) do
    with_validated_callback(organization_id, response, "Flow resume", fn contact ->
      resume_standard(organization_id, result, response, contact)
    end)
  end

  @doc """
  Resume a flow parked on the voice unified-LLM webhook.

  Same validation gate as `resume/3`, but shapes the callback through voice
  post-processing (NMT + TTS) before resuming the flow.
  """
  @spec voice_resume(non_neg_integer(), map(), map()) :: :ok
  def voice_resume(organization_id, result, response) do
    with_validated_callback(organization_id, response, "Voice flow resume", fn contact ->
      resume_voice(organization_id, result, response, contact)
    end)
  end

  # Restores tenant context, validates the callback signature and resolves the
  # contact BEFORE running `fun`. A forged/unsigned callback must not drive any
  # log writes, metrics, or flow resume — so validation comes first.
  @spec with_validated_callback(non_neg_integer(), map(), String.t(), (Contact.t() -> any())) ::
          :ok
  defp with_validated_callback(organization_id, response, label, fun) do
    Repo.put_process_state(organization_id)
    organization = Partners.organization(organization_id)

    with true <- validate_request(organization_id, response),
         {:ok, contact} <-
           Repo.fetch_by(Contact, %{
             id: response["contact_id"],
             organization_id: organization.id
           }) do
      fun.(contact)
    else
      false ->
        Logger.warning(
          "#{label} validation failed: organization_id=#{organization_id}, flow_id=#{response["flow_id"]}, contact_id=#{response["contact_id"]}, webhook_log_id=#{response["webhook_log_id"]}, result_name=#{response["result_name"]}, timestamp=#{response["timestamp"]}"
        )

      {:error, reason} ->
        Logger.warning("#{label} contact lookup failed: #{inspect(reason)}")
    end

    :ok
  end

  @spec resume_standard(non_neg_integer(), map(), map(), Contact.t()) :: :ok
  defp resume_standard(organization_id, result, response, contact) do
    log_message = %{
      success: result["success"],
      message: response["message"] || result["error"],
      error_type: result["error_type"],
      reason: result["reason"],
      thread_id: response["thread_id"]
    }

    if response["webhook_log_id"], do: update_log(response["webhook_log_id"], log_message)

    track_callback_outcome(result, response)

    response_key = response["result_name"] || "response"

    FlowContext.resume_contact_flow(
      contact,
      response["flow_id"],
      %{response_key => response},
      resume_message(result, response, organization_id)
    )
    |> log_resume_error(response)
  end

  @spec resume_voice(non_neg_integer(), map(), map(), Contact.t()) :: :ok
  defp resume_voice(organization_id, result, response, contact) do
    response_key = response["result_name"] || "response"

    message =
      if result["success"],
        do: Messages.create_temp_message(organization_id, "Success"),
        else: Messages.create_temp_message(organization_id, "Failure")

    voice_response =
      VoiceFilesearchGpt.voice_post_process(organization_id, result["success"], response)

    if response["webhook_log_id"],
      do: update_log(response["webhook_log_id"], voice_response)

    track_callback_outcome(result, response)

    case FlowContext.resume_contact_flow(
           contact,
           response["flow_id"],
           %{response_key => voice_response},
           message
         ) do
      {:ok, _context, _messages} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Voice flow resume failed for contact #{contact.id}, flow #{response["flow_id"]}: #{inspect(reason)}"
        )

        Instrumentation.report_resume_failure(response, reason)
    end
  end

  # Picks the wakeup message for the resumed flow. nil keeps compatibility with non-Kaapi
  # webhook responses (falls back to the default behavior).
  @spec resume_message(map(), map(), non_neg_integer()) :: Messages.Message.t() | nil
  defp resume_message(result, response, organization_id) do
    case {result["success"], response["webhook_log_id"]} do
      {true, nil} -> Messages.create_temp_message(organization_id, "No Response")
      {true, _} -> Messages.create_temp_message(organization_id, "Success")
      {false, _} -> Messages.create_temp_message(organization_id, "Failure")
      _ -> nil
    end
  end

  @spec log_resume_error(tuple(), map()) :: :ok
  defp log_resume_error({:ok, _context, _messages}, _response), do: :ok

  defp log_resume_error({:error, reason}, response) do
    Logger.warning(
      "Flow resume failed for contact #{response["contact_id"]}, flow #{response["flow_id"]}: #{inspect(reason)}"
    )

    Instrumentation.report_resume_failure(response, reason)
  end

  @doc """
  Parse the raw Kaapi/external callback body into the internal response map
  consumed by `resume/3` and `voice_resume/3`.
  """
  # New format from filesearch-gpt (/api/v1/llm/call):
  # metadata (org_id, flow_id, signature, etc.) is in result["metadata"]
  # Map the response_id/conversation_id to thread_id, since we treat response_id as the thread ID in Glific
  # For TTS (output type "audio"), "message" holds the raw base64 and "output_type" is set
  # so that maybe_upload_tts_audio/1 can upload it to GCS and replace "message" with the media URL.
  @spec parse_callback_response(map()) :: map()
  def parse_callback_response(%{"metadata" => metadata, "data" => data})
      when is_map(metadata) and map_size(metadata) > 0 do
    response_data = get_in(data || %{}, ["response"]) || %{}
    output = get_in(response_data, ["output"]) || %{}
    output_type = get_in(output, ["type"])
    conversation_id = response_data["conversation_id"]

    metadata
    |> Map.put("thread_id", conversation_id)
    |> Map.put("output_type", output_type)
    |> Map.put("message", get_in(output, ["content", "value"]))
  end

  # Old format from call_and_wait (/api/v1/responses):
  def parse_callback_response(%{"data" => data}) do
    response = data || %{}
    Map.put(response, "thread_id", response["response_id"])
  end

  # Fallback for unexpected formats
  def parse_callback_response(result) do
    Logger.warning(
      "Unexpected callback response format received from Kaapi or external service: #{inspect(result)}"
    )

    %{}
  end

  @doc """
  Upload base64 TTS audio (when present) to GCS, replacing the inline payload
  with the media URL. Called from the request process so large binaries are not
  copied into the supervised resume task.
  """
  @spec maybe_upload_tts_audio(map()) :: map()
  def maybe_upload_tts_audio(%{"output_type" => "audio", "message" => base64_audio} = response) do
    {:ok, organization_id} = response["organization_id"] |> Glific.parse_maybe_integer()
    media_url = upload_tts_audio(base64_audio, organization_id)

    response
    |> Map.put("message", media_url)
  end

  def maybe_upload_tts_audio(response), do: response

  @spec upload_tts_audio(String.t() | nil, non_neg_integer()) :: String.t() | nil
  defp upload_tts_audio(nil, _organization_id), do: nil

  defp upload_tts_audio(base64_audio, organization_id) do
    uuid = Ecto.UUID.generate()
    remote_name = "Kaapi/outbound/#{uuid}.mp3"
    mp3_file = Path.join(System.tmp_dir!(), "#{uuid}.mp3")

    with {:ok, decoded_audio} <- Base.decode64(base64_audio),
         :ok <- File.write(mp3_file, decoded_audio),
         {:ok, media_meta} <- GcsWorker.upload_media(mp3_file, remote_name, organization_id) do
      File.rm(mp3_file)
      media_meta.url
    else
      error ->
        File.rm(mp3_file)
        Logger.error("Kaapi TTS upload failed: #{inspect(error)}")
        nil
    end
  end

  @spec track_callback_outcome(map(), map()) :: :ok
  defp track_callback_outcome(result, response) do
    status = if result["success"], do: "success", else: "failure"
    track_webhook_count(response["webhook_name"], status)
    track_kaapi_latency(response, status)
    # Routes callback failure reporting through the centralised Instrumentation module
    # so all failure events share the same AppSignal namespace and tag shape.
    Instrumentation.report_callback_failure(result, response)
  end

  # Records latency for an async webhook callback.
  @spec track_kaapi_latency(map(), String.t()) :: :ok
  defp track_kaapi_latency(%{"timestamp" => timestamp} = response, status)
       when is_integer(timestamp) do
    now = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    duration_ms = (now - timestamp) / 1_000

    case response["call_type"] do
      nil ->
        :ok

      call_type ->
        Appsignal.add_distribution_value("kaapi_llm_latency", duration_ms, %{
          call_type: call_type
        })
    end

    track_webhook_latency(response["webhook_name"], status, duration_ms)
  end

  defp track_kaapi_latency(_response, _status), do: :ok

  @spec validate_request(non_neg_integer(), map()) :: boolean()
  defp validate_request(_new_organization_id, fields) when map_size(fields) == 0,
    do: false

  defp validate_request(new_organization_id, fields) do
    if missing_callback_fields?(fields),
      do: false,
      else: do_validate_request(new_organization_id, fields)
  end

  @spec missing_callback_fields?(map()) :: boolean()
  defp missing_callback_fields?(fields) do
    Enum.any?(
      ["organization_id", "flow_id", "contact_id", "timestamp", "signature"],
      &is_nil(Map.get(fields, &1))
    )
  end

  @spec do_validate_request(non_neg_integer(), map()) :: boolean()
  defp do_validate_request(new_organization_id, fields) do
    do_validate_signature(
      new_organization_id,
      fields["flow_id"],
      fields["contact_id"],
      fields["organization_id"],
      fields["timestamp"],
      fields["signature"]
    )
  end

  @spec do_validate_signature(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          integer(),
          String.t()
        ) :: boolean()
  defp do_validate_signature(
         new_organization_id,
         flow_id,
         contact_id,
         organization_id,
         timestamp,
         signature
       ) do
    signature_payload = %{
      "organization_id" => organization_id,
      "flow_id" => flow_id,
      "contact_id" => contact_id,
      "timestamp" => timestamp
    }

    new_signature =
      Glific.signature(
        organization_id,
        Jason.encode!(signature_payload),
        timestamp
      )

    new_timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    cond do
      new_organization_id != organization_id -> false
      new_signature != signature -> false
      new_timestamp > timestamp + 15 * 60 * 1_000_000 -> false
      true -> true
    end
  end
end
