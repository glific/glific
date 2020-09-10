defmodule Glific.Dialogflow.Sessions do
  @moduledoc """
  Helper to help manage intents
  """

  alias Glific.Messages.Message

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

    %{
      :method => :post,
      :path => "sessions/#{session_id}:detectIntent",
      :body => body,
      :message => Message.to_minimal_map(message)
    }
    |> Glific.Dialogflow.Worker.new()
    |> Oban.insert()
  end
end
