defmodule Glific.Flowex.Sessions do
  @moduledoc """
  Helper to help manage intents
  """

  alias Glific.Flowex

  @doc """
  Function to communicate with dialogflow to detect the intent of the request
  """
  @spec detect_intent(String.t, String.t, String.t, String.t) :: tuple
  def detect_intent(project, text, session_id, language \\ "en") do
    body = %{
      queryInput: %{
        text: %{
          text: text,
          languageCode: language
        }
      }
    }

    Flowex.request(project, :post, "sessions/#{session_id}:detectIntent", body)
  end
end
