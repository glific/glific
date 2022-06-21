defmodule Glific.GoogleASR do
  @moduledoc """
  This is a module to convert speech to text
  """
  @hackney Tesla.Adapter.Hackney

  require Logger

  alias Glific.{
    Partners
  }


  @spec new_client(non_neg_integer) :: Tesla.Client.t()
  def new_client(org_id) do
    token = Partners.get_goth_token(org_id, "dialogflow").token

    middleware = [
      {Tesla.Middleware.BaseUrl, "https://speech.googleapis.com/"},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
        {"Authorization", "Bearer #{token}"},
        {"Content-Type", "application/json"}
       ]
    }
    ]

    Tesla.client(middleware, @hackney)
  end

  @spec speech_to_text(non_neg_integer, String.t()) :: any
  def speech_to_text(org_id, uri) do
    url = "v1/speech:recognize"
    body = %{
      "config" => %{
          "encoding" => "OGG_OPUS",
          "sampleRateHertz" => 16000,
          "languageCode" => "hi-IN",
          "profanityFilter" => true
      },
      "audio" => %{
          "uri" => uri
      }
    }

    {:ok, result} = Tesla.post(new_client(org_id), url, body)

    case result.body["error"] do
      nil ->
        case result.body["results"] do
          nil ->
            nil

          res ->
            res |> get_in([Access.at(0), "alternatives"]) |> List.first()
        end

      res ->
        Logger.info("Oops! Something is wrong, #{inspect(res["message"])}")
    end
  end
end
