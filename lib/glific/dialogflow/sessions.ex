defmodule Glific.Dialogflow.Sessions do
  @moduledoc """
  Helper to help manage intents
  """

  alias Glific.Dialogflow

  @doc """
  Function to communicate with dialogflow to detect the intent of the request
  """

  @spec detect_intent(map(), String.t(), String.t()) :: tuple
  def detect_intent(message, session_id, language \\ "en") do
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


  defp handle_response({:ok, response}, message) do
    Glific.Processor.Helper.add_dialogflow_tag(message, response["queryResult"])
  end

  defp handle_response(response, _) do
    IO.inspect("error response")
    IO.inspect(response)
  end
end
