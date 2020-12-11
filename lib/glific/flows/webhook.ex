defmodule Glific.Flows.Webhook do
  @moduledoc """
  Lets wrap all webhook functionality here as we try and get
  a better handle on the breadth and depth of webhooks
  """

  alias Glific.Extensions
  alias Glific.Flows.{Action, FlowContext, WebhookLog}
  alias Glific.Contacts
  alias Glific.Flows.MessageVarParser

  @spec add_signature(Keyword.t(), non_neg_integer, String.t()) :: Keyword.t()
  defp add_signature(headers, organization_id, body) do
    now = System.system_time(:second)
    sig = "t=#{now},v1=#{Glific.signature(organization_id, body, now)}"

    [
      {"X-Glific-Signature", sig}
      | headers
    ]
  end

  @doc """
  Execute a webhook action, could be either get or post for now
  """
  @spec execute(Action.t(), FlowContext.t()) :: map() | nil
  def execute(action, context) do
    headers =
      Keyword.new(
        action.headers,
        fn {k, v} -> {String.to_existing_atom(k), v} end
      )

    case String.downcase(action.method) do
      "get" -> get(action, context, headers)
      "post" -> post(action, context, headers)
      "patch" -> patch(action, context, headers)
    end
  end

  @spec create_log(Action.t(), map(), Keyword.t(), FlowContext.t()) :: WebhookLog.t()
  defp create_log(action, body, headers, context) do
    {:ok, webhook_log} =
      %{
        request_json: body,
        request_headers: Map.new(headers),
        url: action.url,
        method: action.method,
        organization_id: context.organization_id,
        flow_id: context.flow_id,
        contact_id: context.contact.id
      }
      |> WebhookLog.create_webhook_log()

    webhook_log
  end

  @spec update_log(map(), WebhookLog.t()) :: {:ok, WebhookLog.t()}
  defp update_log(message, webhook_log) when is_map(message) do
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

  @spec update_log(String.t(), WebhookLog.t()) :: {:ok, WebhookLog.t()}
  defp update_log(error_message, webhook_log) do
    attrs = %{
      error: error_message
    }

    webhook_log
    |> WebhookLog.update_webhook_log(attrs)
  end

  @spec create_body(FlowContext.t(), String.t()) :: {map(), String.t()}
  defp create_body(context, action_body) do
    action_body = action_body

    |> MessageVarParser.parse(%{"contact" => Contacts.get_contact_field_map(context.contact_id)})
    |> MessageVarParser.parse_results(context.results)
    default_payload = %{
      contact: %{
        name: context.contact.name,
        phone: context.contact.phone,
        fields: context.contact.fields
      },
      results: context.results
    }
    {:ok, default_contact} = Jason.encode(default_payload.contact)
    action_body = action_body |> String.replace("@contact", default_contact)
    {:ok, default_results} = Jason.encode(default_payload.results)
    action_body = action_body |> String.replace("@results", default_results)
    IO.inspect("debug001-action_body")
    # IO.inspect(action_body)
    # {:ok, action_body} = Jason.decode(action_body)
    # IO.inspect(Jason.decode(action_body))
    IO.inspect(action_body)

    IO.inspect({Jason.decode(action_body), action_body})
    ## we need to convert the string to map.
    ## Jason.decode is not working because flow editor
    ## is not converting it to the valid Json
    # {:ok, body} = Jason.encode(action_payload)
    # IO.inspect(body)
    {Jason.decode(action_body), action_body}
  end

  @spec post(Action.t(), FlowContext.t(), Keyword.t()) :: map() | nil
  defp post(action, context, headers) do
    {map, body} = create_body(context, action.body)
    # headers = add_signature(headers, context.organization_id, body)

    # webhook_log = create_log(action, map, headers, context)

    # case Tesla.post(action.url, body, headers: headers) do
    #   {:ok, %Tesla.Env{status: 200} = message} ->
    #     update_log(message, webhook_log)

    #     message.body
    #     |> Jason.decode!()
    #     |> Map.get("results")

    #   {:ok, %Tesla.Env{} = message} ->
    #     update_log(message, webhook_log)
    #     nil

    #   {:error, error_message} ->
    #     error_message
    #     |> inspect()
    #     |> update_log(webhook_log)

    #     nil
    # end
    nil
  end

  # Send a get request, and if success, sned the json map back
  @spec get(atom() | Action.t(), FlowContext.t(), Keyword.t()) :: map() | nil
  defp get(action, context, headers) do
    # The get is an empty body
    headers = add_signature(headers, context.organization_id, "")

    webhook_log = create_log(action, %{}, headers, context)

    case Tesla.get(action.url, headers: headers) do
      {:ok, %Tesla.Env{status: 200} = message} ->
        update_log(message, webhook_log)
        message.body |> Jason.decode!()

      {:ok, %Tesla.Env{} = message} ->
        update_log(message, webhook_log)
        nil

      {:error, error_message} ->
        error_message
        |> inspect()
        |> update_log(webhook_log)

        nil
    end
  end

  # we special case the patch request for now to call a module and function that is specific to the
  # organization. We dynamically compile and load this code
  @spec patch(Action.t(), FlowContext.t(), Keyword.t()) :: map() | nil
  defp patch(action, context, headers) do
    {map, body} = create_body(context, action.body)
    headers = add_signature(headers, context.organization_id, body)

    webhook_log = create_log(action, map, headers, context)

    name = Keyword.get(headers, :Extension)

    # For calls within glific, dont create strings, use maps to communicate
    result = Extensions.execute(name, map)

    webhook_log
    |> WebhookLog.update_webhook_log(%{
      response_json: result,
      status_code: 200
    })

    result
  end
end
