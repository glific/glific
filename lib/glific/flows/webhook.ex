defmodule Glific.Flows.Webhook do
  @moduledoc """
  Lets wrap all webhook functionality here as we try and get
  a better handle on the breadth and depth of webhooks
  """

  alias Glific.Flows.{Action, FlowContext, WebhookLog}

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

    webhook_log = create_log(action, context)

    case String.downcase(action.method) do
      "get" -> get(action, context, headers, webhook_log)
      "post" -> post(action, context, headers, webhook_log)
      "patch" -> patch(action, context, headers, webhook_log)
    end
  end

  @spec create_log(Action.t(), FlowContext.t()) :: WebhookLog.t()
  defp create_log(action, context) do
    {:ok, webhook_log} =
      %{
        request_json: action.body,
        request_headers: [action.headers],
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
    attrs = %{
      response_json: message.body |> Jason.decode!(),
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

  @spec post(Action.t(), FlowContext.t(), Keyword.t(), WebhookLog.t()) :: map() | nil
  defp post(action, context, headers, webhook_log) do
    {:ok, body} =
      %{
        contact: %{
          name: context.contact.name,
          phone: context.contact.phone,
          fields: context.contact.fields
        },
        results: context.results
      }
      |> Jason.encode()

    headers = add_signature(headers, context.organization_id, body)

    case Tesla.post(action.url, body, headers: headers) do
      {:ok, %Tesla.Env{status: 200} = message} ->
        update_log(message, webhook_log)

        message.body
        |> Jason.decode!()
        |> Map.get("results")

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

  # Send a get request, and if success, sned the json map back
  @spec get(atom() | Action.t(), FlowContext.t(), Keyword.t(), WebhookLog.t()) :: map() | nil
  defp get(action, context, headers, webhook_log) do
    # The get is an empty body
    headers = add_signature(headers, context.organization_id, "")

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
  @spec patch(atom() | Action.t(), FlowContext.t(), Keyword.t(), WebhookLog.t()) :: map() | nil
  defp patch(_action, _context, _headers, _webhook_log) do
  end
end
