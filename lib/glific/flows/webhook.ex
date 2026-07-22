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
    Request
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
    Custom error for Kaapi webhook failures, reported to AppSignal since Kaapi is a backend
    service NGOs can't act on directly.
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

  # Async callbacks without a webhook_log_id (e.g. non-Kaapi resumes) skip the log write.
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

  # An application-level failure map (%{success: false, ...}) records a non-200 status + reason.
  def update_log(webhook_log, %{success: false} = result) do
    reason =
      Map.get(result, :reason) || Map.get(result, :error) || Map.get(result, :message)

    # reason can be a non-binary term (e.g. a decoded JSON map); to_string/1 would raise, so
    # inspect defensively via safe_inspect.
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
        # for job uniqueness
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
      # Webhook name is safe to log; the request payload is omitted to avoid leaking user data.
      Glific.log_exception(error)

      {:error,
       "Calling webhook function #{SafeLog.safe_inspect(function)} threw: #{Exception.message(error)}"}
  end

  # Routes a function-type webhook to the central Dispatcher when registered, else falls back to
  # Glific.Clients.webhook/2 (per-org client modules).
  @spec dispatch_function(String.t(), map(), list()) :: any()
  defp dispatch_function(function, fields, headers) do
    case Registry.lookup(function) do
      module when not is_nil(module) and is_atom(module) ->
        Dispatcher.dispatch(function, fields, headers)

      _ ->
        function |> Glific.Clients.webhook(fields) |> wrap_legacy_result()
    end
  end

  # Per-org client webhooks return a bare map; wrap it in the same typed shape registered nodes
  # use so routing and logging stay uniform. A non-map (shouldn't happen) still routes to Failure
  # via handle/3's `is_map` guard.
  @spec wrap_legacy_result(map()) :: {:ok, map()}
  defp wrap_legacy_result(value), do: {:ok, value}

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

    # Function webhooks get the decoded body enriched with flow metadata; POST/GET keep the raw
    # body string.
    enrichment = %{
      "flow_id" => args["flow_id"],
      "contact_id" => args["contact_id"],
      "webhook_log_id" => webhook_log_id,
      "result_name" => result_name
    }

    result =
      case do_action(method, url, action_input(method, body, enrichment), headers) do
        # Propagate a rate-limit snooze to Oban without logging or routing the flow.
        {:ok, :function, {:snooze, _seconds} = snooze} ->
          snooze

        {:ok, :function, function_result} ->
          log_function_result(webhook_log_id, function_result)
          function_result

        {:ok, %Tesla.Env{status: status} = message} when status in 200..299 ->
          decode_success_response(message, webhook_log_id)

        {:ok, %Tesla.Env{} = message} ->
          update_log(webhook_log_id, "Did not return a 200..299 status code" <> message.body)
          {:error, :unknown, "Webhook did not return a 200..299 status code"}

        {:error, error_message} ->
          reason = SafeLog.safe_inspect(error_message)
          update_log(webhook_log_id, reason)
          {:error, :unknown, reason}
      end

    case result do
      {:snooze, seconds} -> {:snooze, seconds}
      _ -> handle_webhook_result(result, context, result_name, url, organization_id)
    end
  end

  # Logs the unwrapped value of a function webhook's typed result (registered node or wrapped
  # per-org client) to the WebhookLog. A snooze is not logged — the job just reschedules.
  @spec log_function_result(non_neg_integer(), any()) :: any()
  defp log_function_result(webhook_log_id, {:ok, value}), do: update_log(webhook_log_id, value)

  defp log_function_result(webhook_log_id, {:error, _type, reason}),
    do: update_log(webhook_log_id, reason)

  defp log_function_result(_webhook_log_id, {:snooze, _seconds}), do: :ok

  # Decodes a 2xx POST/GET response body into a typed `{:ok, map} | {:error, ...}`. A JSON list is
  # indexed into a map; an undecodable body or non-object routes the flow to Failure.
  @spec decode_success_response(Tesla.Env.t(), non_neg_integer() | nil) :: any()
  defp decode_success_response(message, webhook_log_id) do
    case Jason.decode(message.body) do
      {:ok, list_response} when is_list(list_response) ->
        list_response = format_response(list_response)
        updated_message = Map.put(message, :body, Jason.encode!(list_response))
        update_log(webhook_log_id, updated_message)
        {:ok, list_response}

      {:ok, json_response} ->
        update_log(webhook_log_id, message)
        wrap_decoded_response(format_response(json_response))

      {:error, _error} ->
        update_log(webhook_log_id, "Could not decode message body: " <> message.body)
        {:error, :unknown, "Webhook response body could not be decoded"}
    end
  end

  # format_response can yield a non-map (a scalar JSON body); only a map routes to Success.
  @spec wrap_decoded_response(any()) :: {:ok, map()} | {:error, atom(), String.t()}
  defp wrap_decoded_response(response) when is_map(response), do: {:ok, response}

  defp wrap_decoded_response(_response),
    do: {:error, :unknown, "Webhook response was not a JSON object"}

  @spec action_input(String.t(), String.t(), map()) :: map() | String.t()
  defp action_input("function", body, enrichment),
    do: body |> Jason.decode!() |> Map.merge(enrichment)

  defp action_input(_method, body, _enrichment), do: body

  # For async webhooks a successful ack leaves the flow parked (the callback resumes it via
  # FlowResumeController); a failure wakes it on the Failure branch. Sync webhooks resume now.
  @spec handle_webhook_result(any(), map(), String.t(), String.t(), non_neg_integer()) :: :ok
  defp handle_webhook_result(result, context, result_name, url, organization_id) do
    if Registry.async?(url) do
      case result do
        {:ok, _ack} -> :ok
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

  # Routes a sync webhook result: `{:ok, map}` (with a result_name) stores the map and takes the
  # Success branch; every other shape takes Failure.
  @spec handle(any(), map(), String.t() | nil) :: :ok
  defp handle(result, context_data, result_name) do
    context_id = context_data["id"]

    context =
      Repo.get!(FlowContext, context_id)
      |> Repo.preload(:flow)
      |> Map.put(:delay, context_data["delay"] || 0)
      |> Map.put(:uuids_seen, context_data["uuids_seen"])

    {context, message} =
      case result do
        {:ok, value} when is_map(value) and not is_nil(result_name) ->
          {
            FlowContext.update_results(
              context,
              %{result_name => Map.put(value, :inserted_at, DateTime.utc_now())}
            ),
            Messages.create_temp_message(context.organization_id, "Success")
          }

        _ ->
          {context, Messages.create_temp_message(context.organization_id, "Failure")}
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
  # Async callback resume — the inbound counterpart of execute/2 + perform/1. The controller
  # parses the callback and uploads any TTS audio, then hands off to resume/3; validation,
  # logging, telemetry and the actual flow resume all live here.
  # --------------------------------------------------------------------------

  @doc """
  Resume a flow parked on any async webhook, from the parsed Kaapi callback.
  """
  @spec resume(non_neg_integer(), map(), map()) :: :ok
  def resume(organization_id, result, response) do
    # Stamp callback arrival so the voice node can isolate the Kaapi filesearch round-trip as
    # arrival - dispatch (issue #5290). Harmless for non-voice nodes, which ignore it.
    response =
      Map.put_new_lazy(response, "callback_received_ts", fn ->
        DateTime.utc_now() |> DateTime.to_unix(:microsecond)
      end)

    with_validated_callback(organization_id, response, "Flow resume", fn contact ->
      resume(organization_id, result, response, contact)
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
    maybe_update_log(response["webhook_log_id"], callback_log_message(result, response))

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

  # Route on the response-first outcome (a failed TTS upload overwrites it to success=false, so it
  # goes to Failure even though Kaapi reported success). nil keeps compatibility with non-Kaapi
  # webhook responses (falls back to default behavior).
  @spec resume_message(map(), map(), non_neg_integer()) :: Messages.Message.t() | nil
  defp resume_message(result, response, organization_id) do
    case {Map.get(response, "success", result["success"]), response["webhook_log_id"]} do
      {true, nil} -> Messages.create_temp_message(organization_id, "No Response")
      {true, _} -> Messages.create_temp_message(organization_id, "Success")
      {false, _} -> Messages.create_temp_message(organization_id, "Failure")
      _ -> nil
    end
  end

  # Resume failures are reported to AppSignal via Instrumentation, which already logs.
  @spec report_resume_error(tuple(), map()) :: :ok
  defp report_resume_error({:ok, _context, _messages}, _response), do: :ok

  defp report_resume_error({:error, reason}, response),
    do: Instrumentation.report_resume_failure(response, reason)

  @doc """
  Parse the raw Kaapi/external callback body into the internal response map
  consumed by `resume/3`.
  """
  # New format from filesearch-gpt (/api/v1/llm/call): metadata (org_id, flow_id, signature) is
  # in result["metadata"]; response_id/conversation_id maps to thread_id; for TTS, "message"
  # holds raw base64 with "output_type" set so maybe_upload_tts_audio/1 can upload it to GCS.
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

  # Read the outcome from `response` first, falling back to the raw `result`: normally they agree,
  # but a failed TTS upload overwrites `response` with success=false so the log records the real
  # failure even though Kaapi's `result` reported success.
  @spec callback_log_message(map(), map()) :: map()
  defp callback_log_message(result, response) do
    %{
      success: Map.get(response, "success", result["success"]),
      message: response["message"] || sanitize_kaapi_wording(result["error"]),
      error_type: Map.get(response, "error_type", result["error_type"]),
      reason: sanitize_kaapi_wording(Map.get(response, "reason", result["reason"])),
      thread_id: response["thread_id"]
    }
  end

  # Kaapi's error copy sometimes tells the user to "contact Kaapi" — an internal AI service NGO
  # staff have no way to reach. Point them to Glific support instead.
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
        # Kaapi reported success, but with no stored audio there's nothing to resume with. Overwrite
        # the response outcome to a failure so the normal log/routing path records it and routes to
        # Failure — rather than silently resuming success=true with a nil message.
        response
        |> Map.put("message", nil)
        |> Map.put("success", false)
        |> Map.put("error_type", "tts_upload_failed")
        |> Map.put("reason", reason)
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
      # Surface the actual failure rather than assuming "GCS not enabled": Base.decode64
      # returns :error; GcsWorker.upload_media returns {:error, reason} with the real cause.
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
