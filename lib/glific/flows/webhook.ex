defmodule Glific.Flows.Webhook do
  @moduledoc """
  Lets wrap all webhook functionality here as we try and get
  a better handle on the breadth and depth of webhooks.
  """
  import GlificWeb.Gettext
  require Logger

  alias Glific.{Contacts, Messages, Repo}
  alias Glific.Flows.{Action, FlowContext, MessageVarParser, WebhookLog}

  use Oban.Worker,
    queue: :webhook,
    max_attempts: 2,
    priority: 0

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
    case String.downcase(action.method) do
      "get" -> method(action, context)
      "post" -> method(action, context)
      "function" -> method(action, context)
    end

    nil
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
        contact_id: context.contact.id
      }
      |> WebhookLog.create_webhook_log()

    webhook_log
  end

  @spec update_log(WebhookLog.t() | non_neg_integer, map()) :: {:ok, WebhookLog.t()}
  defp update_log(webhook_log_id, message) when is_integer(webhook_log_id) do
    webhook_log = Repo.get!(WebhookLog, webhook_log_id)
    update_log(webhook_log, message)
  end

  defp update_log(webhook_log, %{body: body} = message) when is_map(message) and body != nil do
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

    webhook_log
    |> WebhookLog.update_webhook_log(attrs)
  end

  # this is when we are storing the return from an internal function call
  defp update_log(webhook_log, result) when is_map(result) do
    attrs = %{
      response_json: result,
      status_code: 200
    }

    webhook_log
    |> WebhookLog.update_webhook_log(attrs)
  end

  @spec update_log(WebhookLog.t(), String.t()) :: {:ok, WebhookLog.t()}
  defp update_log(webhook_log, error_message) do
    attrs = %{
      error: error_message
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
      contact: %{
        id: context.contact.id,
        name: context.contact.name,
        phone: context.contact.phone,
        fields: context.contact.fields
      },
      results: context.results,
      flow: %{name: context.flow.name, id: context.flow.id}
    }

    fields = %{
      "contact" => Contacts.get_contact_field_map(context.contact_id),
      "results" => context.results,
      "flow" => %{name: context.flow.name, id: context.flow.id}
    }

    action_body_map =
      MessageVarParser.parse_map(action_body_map, fields)
      |> Enum.map(fn
        {k, "@contact"} -> {k, default_payload.contact}
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
  @spec create_headers(Action.t(), FlowContext.t()) :: map()
  defp create_headers(action, context) do
    default_payload = %{
      contact: %{
        id: context.contact.id,
        name: context.contact.name,
        phone: context.contact.phone,
        fields: context.contact.fields
      },
      results: context.results
    }

    fields = %{
      "contact" => Contacts.get_contact_field_map(context.contact_id),
      "results" => context.results,
      "flow" => %{name: context.flow.name, id: context.flow.id}
    }

    MessageVarParser.parse_map(action.headers, fields)
    |> Enum.map(fn
      {k, "@contact"} -> {k, default_payload.contact}
      {k, "@results"} -> {k, default_payload.results}
      {k, v} -> {k, v}
    end)
    |> Enum.into(%{})
  end

  @spec do_oban(Action.t(), FlowContext.t(), tuple()) :: any
  defp do_oban(action, context, {map, body}) do
    dynamic_headers = create_headers(action, context)

    headers = add_signature(dynamic_headers, context.organization_id, body)
    webhook_log = create_log(action, map, dynamic_headers, context)

    {:ok, _} =
      __MODULE__.new(%{
        method: String.downcase(action.method),
        url: action.url,
        result_name: action.result_name,
        body: body,
        headers: headers,
        webhook_log_id: webhook_log.id,
        context_id: context.id,
        organization_id: context.organization_id
      })
      |> Oban.insert()
  end

  defp do_action("post", url, body, headers),
    do: Tesla.post(url, body, headers: headers)

  ## We need to figure out a way to send the data with urls.
  ## Currently we can not send the json map as a query string
  ## We will come back on this one in the future.
  defp do_action("get", url, body, headers),
    do:
      Tesla.get(url,
        headers: headers,
        query: [data: body],
        opts: [adapter: [recv_timeout: 10_000]]
      )

  defp do_action("function", function, body, _headers) do
    {
      :ok,
      :function,
      Glific.Clients.webhook(function, Jason.decode!(body))
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
            "context_id" => context_id,
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
              list_response = webhook_list_response_to_map(list_response)
              updated_message = Map.put(message, :body, Jason.encode!(list_response))
              update_log(webhook_log_id, updated_message)
              list_response

            {:ok, json_response} ->
              update_log(webhook_log_id, message)
              json_response

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

    handle(result, context_id, result_name)
  end

  @spec handle(String.t(), non_neg_integer, String.t()) :: :ok
  defp handle(result, context_id, result_name) do
    context =
      Repo.get!(FlowContext, context_id)
      |> Repo.preload(:flow)

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

  @spec webhook_list_response_to_map(any()) :: any()
  defp webhook_list_response_to_map(response_json) when is_list(response_json) do
    Enum.with_index(response_json)
    |> Enum.map(fn {value, index} -> {index, value} end)
    |> Enum.into(%{})
  end

  defp webhook_list_response_to_map(response_json), do: response_json
end
