defmodule Glific.Dialogflow.Sessions do
  @moduledoc """
  Helper to help manage intents
  """

  alias Glific.Dialogflow

  @doc """
  Function to communicate with dialogflow to detect the intent of the request
  """
  @spec detect_intent(String.t(), String.t(), String.t()) :: tuple
  def detect_intent(text, session_id, language \\ "en") do
    body = %{
      queryInput: %{
        text: %{
          text: text,
          languageCode: language
        }
      }
    }

    Dialogflow.request(:post, "sessions/#{session_id}:detectIntent", body)
  end
end
