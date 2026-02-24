defmodule Glific.Flows.Webhook do
  @moduledoc """
  Lets wrap all webhook functionality here as we try and get
  a better handle on the breadth and depth of webhooks.
  """
  use Gettext, backend: GlificWeb.Gettext
  require Logger

  alias Glific.Clients.CommonWebhook
  alias Glific.Flows.{Action, FlowContext, MessageVarParser, WebhookLog}
  alias Glific.Messages
  alias Glific.Messages.Message
  alias Glific.Repo
  alias Glific.ThirdParty.Kaapi

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
    "speech_to_text_with_bhasini",
    "nmt_tts_with_bhasini",
    "call_and_wait"
  ]

  @spec add_signature(map() | nil, non_neg_integer, String.t()) :: map()
  defp add_signature(headers, organization_id, body) do
    now = System.system_time(:second)
    sig = "t=#{now},v1=#{Glific.signature(organization_id, body, now)}"

    Map.put(headers, :"X-Glific-Signature", sig)
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
  Execute a filesearch webhook routed through the unified LLM API (/api/v1/llm/call).
  """
  @spec execute_unified_filesearch(Action.t(), FlowContext.t()) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]}
  def execute_unified_filesearch(action, context) do
    with {:ok, kaapi_secrets} <- Kaapi.fetch_kaapi_creds(context.organization_id),
         api_key when is_binary(api_key) <- Map.get(kaapi_secrets, "api_key") do
      updated_headers = Map.put(action.headers, "X-API-KEY", api_key)
      updated_action = %{action | headers: updated_headers}
      unified_llm_and_wait(updated_action, context, true)
    else
      {:error, _error} ->
        unified_llm_and_wait(action, context, false)
    end
  end

  @doc """
  Execute a filesearch webhook routed through Kaapi responses API (/api/v1/responses).
  """
  @spec execute_kaapi_filesearch(Action.t(), FlowContext.t()) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]}
  def execute_kaapi_filesearch(action, context) do
    with {:ok, kaapi_secrets} <- Kaapi.fetch_kaapi_creds(context.organization_id),
         api_key when is_binary(api_key) <- Map.get(kaapi_secrets, "api_key") do
      updated_headers = Map.put(action.headers, "X-API-KEY", api_key)
      updated_action = %{action | headers: updated_headers}
      webhook_and_wait(updated_action, context, true)
    else
      {:error, _error} ->
        webhook_and_wait(action, context, false)
    end
  end

  @spec create_log(Action.t(), map(), map(), FlowContext.t()) :: WebhookLog.t()
  defp create_log(action, body, headers, context) do
    {:ok, webhook_log} =
      %{
        request_json: body,
        request_headers: headers,
        url: action.url,
        method: action.method,
        organization_id: context.organization_id,
        flow_id: context.flow_id,
        contact_id: context.contact_id,
        wa_group_id: context.wa_group_id,
        flow_context_id: context.id
      }
      |> WebhookLog.create_webhook_log()

    webhook_log
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

  def update_log(webhook_log, result) when is_map(result) do
    attrs = %{
      response_json: result,
      status_code: 200
    }

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

  @spec create_body(FlowContext.t(), String.t()) :: {map(), String.t()} | {:error, String.t()}
  defp create_body(_context, action_body) when action_body in [nil, ""], do: {%{}, "{}"}

  defp create_body(context, action_body) do
    case Jason.decode(action_body) do
      {:ok, action_body_map} ->
        do_create_body(context, action_body_map)

      _ ->
        Logger.info("Error in decoding webhook body #{inspect(action_body)}.")

        {:error,
         dgettext(
           "errors",
           "Error in decoding webhook body. Please check the json body in floweditor"
         )}
    end
  end

  @spec do_create_body(FlowContext.t(), map()) :: {map(), String.t()} | {:error, String.t()}
  defp do_create_body(context, action_body_map) do
    default_payload = %{
      contact: get_contact(context),
      wa_group: get_wa_group(context),
      results: context.results,
      flow: %{name: context.flow.name, id: context.flow.id}
    }

    fields = FlowContext.get_vars_to_parse(context)

    action_body_map =
      MessageVarParser.parse_map(action_body_map, fields)
      |> Enum.map(fn
        {k, "@contact"} -> {k, default_payload.contact}
        {k, "@wa_group"} -> {k, default_payload.wa_group}
        {k, "@results"} -> {k, default_payload.results}
        {k, v} -> {k, v}
      end)
      |> Enum.into(%{})
      |> Map.put("organization_id", context.organization_id)

    Jason.encode(action_body_map)
    |> case do
      {:ok, action_body} ->
        {action_body_map, action_body}

      _ ->
        Logger.info("Error in encoding webhook body #{inspect(action_body_map)}.")

        {:error,
         dgettext(
           "errors",
           "Error in encoding webhook body. Please check the json body in floweditor"
         )}
    end
  end

  @spec get_contact(FlowContext.t()) :: map()
  defp get_contact(%FlowContext{contact_id: contact_id} = context) when contact_id != nil do
    %{
      id: context.contact.id,
      name: context.contact.name,
      phone: context.contact.phone,
      fields: context.contact.fields
    }
  end

  defp get_contact(_context), do: %{}

  @spec get_wa_group(FlowContext.t()) :: map()
  defp get_wa_group(%FlowContext{wa_group_id: wa_group_id} = context) when wa_group_id != nil do
    %{
      id: context.wa_group.id,
      label: context.wa_group.label,
      wa_managed_phone_id: context.wa_group.wa_managed_phone_id
    }
  end

  defp get_wa_group(_context), do: %{}

  # method can be either a get or a post. The do_oban function
  # does the right thing based on if it is a get or post
  @spec method(Action.t(), FlowContext.t()) :: nil
  defp method(action, context) do
    case create_body(context, action.body) do
      {:error, message} ->
        action
        |> create_log(%{}, action.headers, context)
        |> update_log(message)

      {map, body} ->
        do_oban(action, context, {map, body})
    end

    nil
  end

  # THis function will create a dynamic headers
  @spec parse_header_and_url(Action.t(), FlowContext.t()) :: map()
  defp parse_header_and_url(action, context) do
    fields = FlowContext.get_vars_to_parse(context)

    header = MessageVarParser.parse_map(action.headers, fields)
    url = MessageVarParser.parse(action.url, fields)

    %{header: header, url: url}
  end

  @spec do_oban(Action.t(), FlowContext.t(), tuple()) :: any
  defp do_oban(action, context, {map, body}) do
    parsed_attrs = parse_header_and_url(action, context)

    headers = add_signature(parsed_attrs.header, context.organization_id, body)
    action = Map.put(action, :url, parsed_attrs.url)
    webhook_log = create_log(action, map, parsed_attrs.header, context)

    payload =
      %{
        method: String.downcase(action.method),
        url: parsed_attrs.url,
        result_name: action.result_name,
        body: body,
        headers: headers,
        webhook_log_id: webhook_log.id,
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

  @spec do_action(String.t(), String.t(), map(), list()) :: any
  defp do_action("post", url, body, headers),
    do: Tesla.post(url, body, headers: headers)

  defp do_action("get", url, body, headers),
    do:
      Tesla.get(url,
        headers: headers,
        query: Enum.into(Jason.decode!(body), []),
        opts: [adapter: [recv_timeout: 10_000]]
      )

  defp do_action("function", function, body, headers) do
    {
      :ok,
      :function,
      Glific.Clients.webhook(function, Jason.decode!(body), headers)
    }
  rescue
    error ->
      error_message =
        "Calling webhook function threw an exception, error: #{inspect(error)} , args: #{inspect(function)}, object: #{inspect(body)},"

      Logger.error(error_message)
      Appsignal.send_error(:error, error_message, __STACKTRACE__)
      {:error, error_message}
  end

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, :string}
  def perform(
        %Oban.Job{
          args: %{
            "method" => method,
            "url" => url,
            "result_name" => result_name,
            "body" => body,
            "headers" => headers,
            "webhook_log_id" => webhook_log_id,
            "context" => context,
            "organization_id" => organization_id
          }
        } = _job
      ) do
    Repo.put_process_state(organization_id)

    headers = Enum.reduce(headers, [], fn {k, v}, acc -> acc ++ [{k, v}] end)

    result =
      case do_action(method, url, body, headers) do
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

    handle(result, context, result_name)
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

  @doc """
  The function updates the flow_context and waits for the unified LLM API to send a response.
  """
  @spec unified_llm_and_wait(map(), FlowContext.t(), boolean()) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]}
  def unified_llm_and_wait(action, context, is_active?) do
    parsed_attrs = parse_header_and_url(action, context)
    failure_message = Messages.create_temp_message(context.organization_id, "Failure")

    case create_body(context, action.body) do
      {:error, message} ->
        webhook_log = create_log(action, %{}, action.headers, context)
        update_log(webhook_log, message)
        {:ok, context, [failure_message]}

      {fields, body} ->
        webhook_log = create_log(action, fields, action.headers, context)

        params = %{
          action: action,
          context: context,
          webhook_log: webhook_log,
          fields: fields,
          body: body,
          headers: parsed_attrs.header
        }

        do_unified_llm_and_wait(params, is_active?, failure_message)
    end
  end

  @spec do_unified_llm_and_wait(map(), boolean(), Message.t()) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]}
  defp do_unified_llm_and_wait(
         %{webhook_log: webhook_log, context: context} = _params,
         false,
         failure_message
       ) do
    update_log(webhook_log.id, "Kaapi is not active")

    Appsignal.send_error(
      %Error{
        message: "Kaapi is not active",
        organization_id: context.organization_id
      },
      []
    )

    {:ok, context, [failure_message]}
  end

  defp do_unified_llm_and_wait(params, true, failure_message) do
    webhook_log_id = params.webhook_log.id

    fields =
      params.fields
      |> Map.put("webhook_log_id", webhook_log_id)
      |> Map.put("result_name", params.action.result_name)
      |> Map.put("flow_id", params.context.flow_id)
      |> Map.put("contact_id", params.context.contact_id)

    headers =
      params.headers
      |> add_signature(params.context.organization_id, params.body)
      |> Enum.reduce([], fn {k, v}, acc -> acc ++ [{k, v}] end)

    process_unified_llm_call(%{
      webhook_log_id: webhook_log_id,
      fields: fields,
      headers: headers,
      action: params.action,
      context: params.context,
      failure_message: failure_message
    })
  end

  @spec process_unified_llm_call(map()) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]}
  defp process_unified_llm_call(params) do
    response = CommonWebhook.webhook("unified-llm-call", params.fields, params.headers)

    case response do
      %{success: true, data: data} ->
        update_log(params.webhook_log_id, data)
        wait_time = params.action.wait_time || 60
        update_context_for_wait(params.context, wait_time)

      %{success: false, reason: data} ->
        update_log(params.webhook_log_id, data)
        {:ok, params.context, [params.failure_message]}

      _ ->
        update_log(params.webhook_log_id, "Something went wrong")
        {:ok, params.context, [params.failure_message]}
    end
  end

  @doc """
  The function updates the flow_context and waits for Kaapi to send a response.
  """
  @spec webhook_and_wait(map(), FlowContext.t(), boolean()) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]}
  def webhook_and_wait(action, context, is_active?) do
    parsed_attrs = parse_header_and_url(action, context)
    failure_message = Messages.create_temp_message(context.organization_id, "Failure")

    case create_body(context, action.body) do
      {:error, message} ->
        webhook_log = create_log(action, %{}, action.headers, context)
        update_log(webhook_log, message)
        {:ok, context, [failure_message]}

      {fields, body} ->
        webhook_log = create_log(action, fields, action.headers, context)

        params = %{
          action: action,
          context: context,
          webhook_log: webhook_log,
          fields: fields,
          body: body,
          headers: parsed_attrs.header
        }

        do_webhook_and_wait(params, is_active?, failure_message)
    end
  end

  @spec do_webhook_and_wait(map(), boolean(), Message.t()) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]}
  defp do_webhook_and_wait(
         %{webhook_log: webhook_log, context: context} = _params,
         false,
         failure_message
       ) do
    update_log(webhook_log.id, "Kaapi is not active")

    Appsignal.send_error(
      %Error{message: "Kaapi is not active (org_id=#{context.organization_id})"},
      []
    )

    {:ok, context, [failure_message]}
  end

  defp do_webhook_and_wait(params, true, failure_message) do
    webhook_log_id = params.webhook_log.id

    fields =
      params.fields
      |> Map.put("webhook_log_id", webhook_log_id)
      |> Map.put("result_name", params.action.result_name)
      |> Map.put("flow_id", params.context.flow_id)
      |> Map.put("contact_id", params.context.contact_id)

    headers =
      params.headers
      |> add_signature(params.context.organization_id, params.body)
      |> Enum.reduce([], fn {k, v}, acc -> acc ++ [{k, v}] end)

    process_call_and_wait(%{
      webhook_log_id: webhook_log_id,
      fields: fields,
      headers: headers,
      action: params.action,
      context: params.context,
      failure_message: failure_message
    })
  end

  @spec process_call_and_wait(map()) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]}
  defp process_call_and_wait(params) do
    response = CommonWebhook.webhook("call_and_wait", params.fields, params.headers)

    case response do
      %{success: true, data: data} ->
        update_log(params.webhook_log_id, data)
        wait_time = params.action.wait_time || 60
        update_context_for_wait(params.context, wait_time)

      %{success: false, reason: data} ->
        update_log(params.webhook_log_id, data)
        {:ok, params.context, [params.failure_message]}

      _ ->
        update_log(params.webhook_log_id, "Something went wrong")
        {:ok, params.context, [params.failure_message]}
    end
  end

  @spec update_context_for_wait(FlowContext.t(), integer()) ::
          {:wait, FlowContext.t(), []}
  defp update_context_for_wait(context, wait_time) do
    {:ok, context} =
      FlowContext.update_flow_context(
        context,
        %{
          wakeup_at: DateTime.add(DateTime.utc_now(), wait_time),
          is_background_flow: context.flow.is_background,
          is_await_result: true
        }
      )

    {:wait, context, []}
  end
end
