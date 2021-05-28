defmodule Glific.Dialogflow.Sessions do
  @moduledoc """
  Helper to help manage intents
  """

  alias Glific.{
    Dialogflow,
    Dialogflow.SessionWorker,
    Flows.FlowContext,
    Messages,
    Messages.Message,
    Repo
  }

  @doc """
  Add message to queue worker to detect the intent
  """
  @spec detect_intent(Message.t(), non_neg_integer, String.t()) :: :ok
  def detect_intent(nil, _, _), do: :ok

  def detect_intent(message, context_id, result_name) do
    %{
      path: message.session_uuid,
      locale: message.contact.language.locale,
      message: Message.to_minimal_map(message),
      context_id: context_id,
      result_name: result_name
    }
    |> SessionWorker.new()
    |> Oban.insert()

    :ok
  end

  @doc """
  Function to communicate with dialogflow to detect the intent of the request
  """
  @spec make_request(map(), String.t(), String.t(), Keyword.t()) :: :ok | {:error, :string}
  def make_request(message, session_id, language \\ "en", opts) do
    Repo.put_process_state(message.organization_id)

    body = %{
      queryInput: %{
        text: %{
          text: message.body,
          languageCode: language
        }
      }
    }

    Dialogflow.request(
      message.organization_id,
      :post,
      "sessions/#{session_id}:detectIntent",
      body
    )
    |> handle_response(opts[:context_id], opts[:result_name])
  end

  @spec handle_response(tuple(), non_neg_integer, String.t()) :: :ok | {:error, :string}
  defp handle_response({:ok, response}, context_id, result_name) do
    intent = get_in(response, ["queryResult", "intent", "displayName"])

    context =
      Repo.get!(FlowContext, context_id)
      |> Repo.preload(:flow)

    {context, message} =
      if is_nil(intent) do
        {
          context,
          Messages.create_temp_message(context.organization_id, "Failure")
        }
      else
        # update the context with the results from webhook return values
        confidence = get_in(response, ["queryResult", "intentDetectionConfidence"])
        response = get_in(response, ["queryResult", "fulfillmentText"])

        data = %{intent: intent, confidence: confidence, response: response}

        {
          FlowContext.update_results(context, %{result_name => data}),
          Messages.create_temp_message(context.organization_id, "Success")
          |> Map.put(:extra, data)
        }
      end

    FlowContext.wakeup_one(context, message)
    :ok
  end

  defp handle_response(error, _, _), do: {:error, error}
end
