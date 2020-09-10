defmodule Glific.Dialogflow.Sessions do
  @moduledoc """
  Helper to help manage intents
  """

  alias Glific.{
    Dialogflow,
    Dialogflow.Worker,
    Messages.Message,
    Processor.Helper
  }

  @doc """
  Add message to queue worker to detect the intent
  """
  @spec detect_intent(map(), String.t()) :: tuple
  def detect_intent(message, session_id) do
    %{
      :path => session_id,
      :locale => message.contact.language.locale,
      :message => Message.to_minimal_map(message)
    }
    |> Worker.new()
    |> Oban.insert()

    {:ok}
  end

  @doc """
  Function to communicate with dialogflow to detect the intent of the request
  """
  @spec make_request(map(), String.t(), String.t()) :: tuple
  def make_request(message, session_id, language \\ "en") do
    body = %{
      queryInput: %{
        text: %{
          text: message.body,
          languageCode: language
        }
      }
    }

    Dialogflow.request(:post, "sessions/#{session_id}:detectIntent", body)
    |> handle_response(message)
  end

  @spec detect_intent(tuple(), map() | String.t()) :: any()
  defp handle_response({:ok, response}, message),
    do: Helper.add_dialogflow_tag(message, response["queryResult"])

  defp handle_response(error, _), do: {:error, error}
end
