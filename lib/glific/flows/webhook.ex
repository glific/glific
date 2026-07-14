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
    Repo,
    SafeLog
  }

  alias Glific.Flows.{Action, FlowContext, WebhookLog}

  alias Glific.Flows.Webhooks.{
    Dispatcher,
    Instrumentation,
    Registry,
    Request,
    VoiceFilesearchGpt
  }

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

  @non_unique_urls [
    "parse_via_gpt_vision",
    "parse_via_chat_gpt",
    "filesearch-gpt",
    "voice-filesearch-gpt",
    "speech_to_text",
    "text_to_speech"
  ]

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

  # Update the webhook log only when there is one — async callbacks without a
  # webhook_log_id (e.g. non-Kaapi resumes) simply skip the log write.
  @spec maybe_update_log(non_neg_integer() | nil, map() | binary()) :: any()
  defp maybe_update_log(nil, _message), do: :ok
  defp maybe_update_log(webhook_log_id, message), do: update_log(webhook_log_id, message)

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
    # body). to_string/1 would raise on those; inspect/1 produces a safe string
    # for any term.
    error =
      cond do
        is_binary(reason) -> reason
        is_nil(reason) -> "Webhook failure"
        true -> Glific.SafeLog.safe_inspect(reason)
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
    case Request.create_body(context, action.body) do
      {:error, message} ->
        action
        |> Request.create_log(%{}, action.headers, context)
        |> update_log(message)

      {map, body} ->
        do_oban(action, context, {map, body})
    end

    nil
  end

  @spec do_oban(Action.t(), FlowContext.t(), tuple()) :: any
  defp do_oban(action, context, {map, body}) do
    parsed_attrs = Request.parse_header_and_url(action, context)

    headers = Request.add_signature(parsed_attrs.header, context.organization_id, body)
    action = Map.put(action, :url, parsed_attrs.url)
    webhook_log = Request.create_log(action, map, parsed_attrs.header, context)

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

      {:error,
       "Calling webhook function #{SafeLog.safe_inspect(function)} threw: #{Exception.message(error)}"}
  end

  # Routes a function-type webhook to the central Dispatcher when it is registered (sync or
  # async — both run their module's call/2 wrapped in instrumentation), otherwise falls back
  # to Glific.Clients.webhook/2 (per-org client modules).
  @spec dispatch_function(String.t(), map(), list()) :: any()
  defp dispatch_function(function, fields, headers) do
    case Registry.lookup(function) do
      module when not is_nil(module) and is_atom(module) ->
        Dispatcher.dispatch(function, fields, headers)

      _ ->
        Glific.Clients.webhook(function, fields)
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
        # A webhook module (e.g. an STT/TTS rate limit) asked to reschedule: propagate the
        # snooze to Oban without logging or routing the flow — the job re-runs call/2 later.
        {:ok, :function, {:snooze, _seconds} = snooze} ->
          snooze

        {:ok, :function, result} ->
          update_log(webhook_log_id, result)
          result

        {:ok, %Tesla.Env{status: status} = message} when status in 200..299 ->
          decode_success_response(message, webhook_log_id)

        {:ok, %Tesla.Env{} = message} ->
          update_log(webhook_log_id, "Did not return a 200..299 status code" <> message.body)
          nil

        {:error, error_message} ->
          update_log(webhook_log_id, SafeLog.safe_inspect(error_message))
          nil
      end

    case result do
      {:snooze, seconds} -> {:snooze, seconds}
      _ -> handle_webhook_result(result, context, result_name, url, organization_id)
    end
  end

  # Decodes a 2xx POST/GET response body, logs it, and returns the value for the flow.
  # A JSON list is indexed into a map; a JSON map passes through; an undecodable body
  # is logged and routes the flow to Failure (nil).
  @spec decode_success_response(Tesla.Env.t(), non_neg_integer() | nil) :: any()
  defp decode_success_response(message, webhook_log_id) do
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
  end

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
    __MODULE__.new(payload,
      queue: :gpt_webhook_queue,
      unique: nil
    )
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
      resume(organization_id, result, response, contact)
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
      resume_voice_filesearch_gpt(organization_id, result, response, contact)
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
        Logger.warning("#{label} contact lookup failed: #{SafeLog.safe_inspect(reason)}")
    end

    :ok
  end

  @spec resume(non_neg_integer(), map(), map(), Contact.t()) :: :ok
  defp resume(organization_id, result, response, contact) do
    log_message = tts_aware_log_message(result, response)

    maybe_update_log(response["webhook_log_id"], log_message)

    # Route the callback through the Dispatcher: it runs the node's callback/3 (pass-through for
    # STT/TTS/filesearch) inside callback-phase instrumentation, so telemetry + classification
    # happen in one place. The shaped response is what the flow resumes on.
    shaped = Dispatcher.callback(response["webhook_name"], result, response)

    response_key = response["result_name"] || "response"

    FlowContext.resume_contact_flow(
      contact,
      response["flow_id"],
      %{response_key => shaped},
      resume_message(result, response, organization_id)
    )
    |> report_resume_error(response)
  end

  @spec resume_voice_filesearch_gpt(non_neg_integer(), map(), map(), Contact.t()) :: :ok
  defp resume_voice_filesearch_gpt(organization_id, result, response, contact) do
    response_key = response["result_name"] || "response"

    # The Dispatcher runs VoiceFilesearchGpt.callback/3 (NMT + TTS post-processing on success,
    # pass-through on failure) inside callback-phase instrumentation, returning the shaped voice
    # response — the webhook_name is fixed here since this route only serves the voice node.
    voice_response = Dispatcher.callback(VoiceFilesearchGpt.name(), result, response)

    message =
      if result["success"],
        do: Messages.create_temp_message(organization_id, "Success"),
        else: Messages.create_temp_message(organization_id, "Failure")

    maybe_update_log(response["webhook_log_id"], voice_response)

    FlowContext.resume_contact_flow(
      contact,
      response["flow_id"],
      %{response_key => voice_response},
      message
    )
    |> report_resume_error(response)
  end

  # Picks the wakeup message for the resumed flow. nil keeps compatibility with non-Kaapi
  # webhook responses (falls back to the default behavior).
  @spec resume_message(map(), map(), non_neg_integer()) :: Messages.Message.t() | nil
  # A failed TTS audio upload routes the flow to Failure even though Kaapi itself
  # reported success — there's no usable audio to continue the Success branch with.
  defp resume_message(_result, %{"tts_upload_error" => reason}, organization_id)
       when is_binary(reason) do
    Messages.create_temp_message(organization_id, "Failure")
  end

  defp resume_message(result, response, organization_id) do
    case {result["success"], response["webhook_log_id"]} do
      {true, nil} -> Messages.create_temp_message(organization_id, "No Response")
      {true, _} -> Messages.create_temp_message(organization_id, "Success")
      {false, _} -> Messages.create_temp_message(organization_id, "Failure")
      _ -> nil
    end
  end

  # Resume failures are reported to AppSignal (flow_webhooks namespace) via
  # Instrumentation, which already logs — so no separate Logger call here.
  @spec report_resume_error(tuple(), map()) :: :ok
  defp report_resume_error({:ok, _context, _messages}, _response), do: :ok

  defp report_resume_error({:error, reason}, response),
    do: Instrumentation.report_resume_failure(response, reason)

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

    message = get_in(output, ["content", "value"]) |> sanitize_kaapi_wording()

    metadata
    |> Map.put("thread_id", conversation_id)
    |> Map.put("output_type", output_type)
    |> Map.put("message", message)
  end

  # Fallback for unexpected formats
  def parse_callback_response(result) do
    Logger.warning(
      "Unexpected callback response format received from Kaapi or external service: #{SafeLog.safe_inspect(result)}"
    )

    %{}
  end

  # When the TTS audio upload failed (e.g. GCS not enabled), record the failure on the
  # WebhookLog (success: false + reason) so it is visible to the user, instead of a silent
  # success with a nil message. Otherwise build the normal log entry.
  @spec tts_aware_log_message(map(), map()) :: map()
  defp tts_aware_log_message(_result, %{"tts_upload_error" => reason} = response)
       when is_binary(reason) do
    %{
      success: false,
      message: nil,
      error_type: "tts_upload_failed",
      reason: reason,
      thread_id: response["thread_id"]
    }
  end

  defp tts_aware_log_message(result, response) do
    %{
      success: result["success"],
      message: response["message"] || sanitize_kaapi_wording(result["error"]),
      error_type: result["error_type"],
      reason: sanitize_kaapi_wording(result["reason"]),
      thread_id: response["thread_id"]
    }
  end

  # Kaapi's error copy sometimes tells the user to "contact Kaapi" directly — an internal
  # AI service NGO staff have no account with or way to reach. Point them to Glific support
  # instead, since that's who can actually act on the report.
  @spec sanitize_kaapi_wording(String.t() | nil) :: String.t() | nil
  defp sanitize_kaapi_wording(text) when is_binary(text),
    do: String.replace(text, "contact Kaapi", "contact the Glific Team")

  defp sanitize_kaapi_wording(text), do: text

  @doc """
  Upload base64 TTS audio (when present) to GCS, replacing the inline payload
  with the media URL. Called from the request process so large binaries are not
  copied into the supervised resume task.
  """
  @spec maybe_upload_tts_audio(map()) :: map()
  def maybe_upload_tts_audio(%{"output_type" => "audio", "message" => base64_audio} = response) do
    {:ok, organization_id} = response["organization_id"] |> Glific.parse_maybe_integer()

    case upload_tts_audio(base64_audio, organization_id) do
      {:ok, media_url} ->
        Map.put(response, "message", media_url)

      {:error, reason} ->
        # Surface the failure (see tts_aware_log_message/2) rather than silently
        # resuming with success=true and a nil message.
        response
        |> Map.put("message", nil)
        |> Map.put("tts_upload_error", reason)
    end
  end

  def maybe_upload_tts_audio(response), do: response

  @spec upload_tts_audio(String.t() | nil, non_neg_integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp upload_tts_audio(nil, _organization_id), do: {:error, "No TTS audio content received"}

  defp upload_tts_audio(base64_audio, organization_id) do
    uuid = Ecto.UUID.generate()
    remote_name = "Kaapi/outbound/#{uuid}.mp3"
    mp3_file = Path.join(System.tmp_dir!(), "#{uuid}.mp3")

    with {:ok, decoded_audio} <- Base.decode64(base64_audio),
         :ok <- File.write(mp3_file, decoded_audio),
         {:ok, media_meta} <- GcsWorker.upload_media(mp3_file, remote_name, organization_id) do
      File.rm(mp3_file)
      {:ok, media_meta.url}
    else
      # Surface the ACTUAL failure rather than assuming "GCS not enabled":
      # Base.decode64 returns :error; GcsWorker.upload_media returns {:error, reason}
      # where reason already describes the real cause (auth, accountDisabled, etc.,
      # from handle_gcs_error/2).
      :error ->
        File.rm(mp3_file)
        {:error, "TTS audio is not valid base64"}

      {:error, reason} ->
        File.rm(mp3_file)
        message = if is_binary(reason), do: reason, else: SafeLog.safe_inspect(reason)
        {:error, message}
    end
  end

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
