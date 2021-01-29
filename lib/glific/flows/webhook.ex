defmodule Glific.Flows.Webhook do
  @moduledoc """
  Lets wrap all webhook functionality here as we try and get
  a better handle on the breadth and depth of webhooks
  """

  alias Glific.{Contacts, Messages, Repo}
  alias Glific.Flows.{Action, FlowContext, MessageVarParser, WebhookLog}

  use Oban.Worker,
    queue: :webhook,
    max_attempts: 1,
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
      "get" -> get(action, context)
      "post" -> post(action, context)
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

  defp update_log(webhook_log, message) when is_map(message) do
    # handle incorrect json body
    json_body =
      case Jason.decode(message.body) do
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

  @spec update_log(WebhookLog.t(), String.t()) :: {:ok, WebhookLog.t()}
  defp update_log(webhook_log, error_message) do
    attrs = %{
      error: error_message
    }

    webhook_log
    |> WebhookLog.update_webhook_log(attrs)
  end

  @spec create_body(FlowContext.t(), String.t()) :: {map(), String.t()} | {:error, String.t()}
  defp create_body(context, action_body) do
    default_payload = %{
      contact: %{
        name: context.contact.name,
        phone: context.contact.phone,
        fields: context.contact.fields
      },
      results: context.results
    }

    fields = %{
      "contact" => Contacts.get_contact_field_map(context.contact_id),
      "results" => context.results
    }

    {:ok, default_contact} = Jason.encode(default_payload.contact)
    {:ok, default_results} = Jason.encode(default_payload.results)

    action_body =
      action_body
      |> MessageVarParser.parse(fields)
      |> MessageVarParser.parse_results(context.results)
      |> String.replace("\"@contact\"", default_contact)
      |> String.replace("\"@results\"", default_results)

    case Jason.decode(action_body) do
      {:ok, action_body_map} -> {action_body_map, action_body}
      _ -> {:error, "Error in decoding webhook body. Please check the json body in floweditor"}
    end
  end

  @spec post(Action.t(), FlowContext.t()) :: nil
  defp post(action, context) do
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

  @spec do_oban(Action.t(), FlowContext.t(), tuple()) :: nil
  defp do_oban(action, context, {map, body}) do
    headers =
      if is_nil(action.headers),
        do: %{},
        else: action.headers

    headers = add_signature(headers, context.organization_id, body)
    webhook_log = create_log(action, map, headers, context)

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

    nil
  end

  defp do_action("post", url, body, headers),
    do: Tesla.post(url, body, headers: headers)

  defp do_action("get", url, _body, headers),
    do: Tesla.get(url, headers: headers)

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

    headers =
      Keyword.new(
        headers,
        fn {k, v} -> {String.to_existing_atom(k), v} end
      )

    result =
      case do_action(method, url, body, headers) do
        {:ok, %Tesla.Env{status: 200} = message} ->
          case Jason.decode(message.body) do
            {:ok, json_response} ->
              update_log(webhook_log_id, message)
              json_response

            {:error, _error} ->
              update_log(webhook_log_id, "Could not decode message body: " <> message.body)

              nil
          end

        {:ok, %Tesla.Env{} = message} ->
          update_log(webhook_log_id, "Did not return a 200 status code" <> message.body)
          nil

        {:error, error_message} ->
          update_log(webhook_log_id, inspect(error_message))
          nil
      end

    handle(result, context_id, result_name)
  end

  def perform(job) do
    IO.inspect(job, label: "job")
    :ok
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
          FlowContext.update_results(context, result_name, result),
          Messages.create_temp_message(context.organization_id, "Success")
        }
      end

    FlowContext.wakeup_one(context, message)
    :ok
  end

  # Send a get request, and if success, sned the json map back
  @spec get(atom() | Action.t(), FlowContext.t()) :: nil
  defp get(action, context),
    do: do_oban(action, context, {%{}, ""})
end
