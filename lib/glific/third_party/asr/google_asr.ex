defmodule Glific.ASR.GoogleASR do
  @moduledoc """
  This is a module to convert speech to text
  """
  @hackney Tesla.Adapter.Hackney
  use Tesla

  require Logger

  alias Glific.Partners

  @doc """
  This function will take organization_id and the url for audio.
  """

  @spec speech_to_text(non_neg_integer, String.t()) :: any
  def speech_to_text(org_id, uri) do
    {:ok, response} = get(uri)
    content = Base.encode64(response.body)

    url = "v1/speech:recognize"

    body = %{
      "config" => %{
        "encoding" => "OGG_OPUS",
        "sampleRateHertz" => 16_000,
        "languageCode" => "hi-IN",
        "profanityFilter" => true
      },
      "audio" => %{
        "content" => content
      }
    }

    {:ok, result} = post(new_client(org_id), url, body)

    case result.body["error"] do
      nil ->
        successful_result_for_speech_to_text(result)

      res ->
        Logger.info("Oops! Something is wrong, #{inspect(res["message"])}")
    end
  end

  @spec successful_result_for_speech_to_text(map()) :: map() | {:error, String.t()}
  defp successful_result_for_speech_to_text(result) do
    case result.body["results"] do
      nil ->
        {:error, "Please check the link or Send the audio again"}

      res ->
        res |> get_in([Access.at(0), "alternatives"]) |> List.first()
    end
  end

  @spec new_client(non_neg_integer) :: Tesla.Client.t()
  defp new_client(org_id) do
    token = Partners.get_goth_token(org_id, "dialogflow").token

    middleware = [
      {Tesla.Middleware.BaseUrl, "https://speech.googleapis.com/"},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{token}"},
         {"Content-Type", "application/json"}
       ]}
    ]

    Tesla.client(middleware, @hackney)
  end
end
