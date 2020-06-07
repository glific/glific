defmodule Glific.Flowex.Intents do
  @moduledoc """
  The main intents module which stiches it all together
  """

  alias Glific.Flowex

  @doc """
  List all the intents of the agent per pageToken.
  """
  @spec list(String.t, String.t, String.t, String.t | nil, list) :: tuple
  def list(project, language \\ "en", view \\ "INTENT_VIEW_UNSPECIFIED", token \\ nil, acc \\ []) do
    case list_by_page(project, language, view, 100, token) do
      {:ok, %{"intents" => intents, "nextPageToken" => nextPageToken}} ->
        list(project, language, view, nextPageToken, acc ++ intents)
      {:ok,  %{"intents" => intents}} ->
        {:ok, acc ++ intents}
      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  List an agent's intents by pageToken and defining page size.
  """
  @spec list_by_page(String.t, String.t, String.t, integer, String.t | nil) :: tuple
  def list_by_page(project, language \\ "en", view \\ "INTENT_VIEW_UNSPECIFIED", pageSize \\ 100, token \\ nil) do
    url =
      "intents?languageCode=#{language}&intentView=#{view}&" <>
      "pageSize=#{pageSize}&pageToken=#{token}"

    Flowex.request(project, :get, url, "")
  end

  @doc """
  Get an intent for a specific id
  """
  @spec get(String.t, String.t, String.t, String.t) :: tuple
  def get(project, id, language \\ "en", view \\ "INTENT_VIEW_UNSPECIFIED") do
    url = "intents/#{id}?languageCode=#{language}&intentView=#{view}"

    Flowex.request(project, :get, url, "")
  end

  @doc """
  Create an intent
  """
  @spec create(String.t, map, String.t) :: tuple
  def create(project, body, language \\ "es") do
    url = "intents?languageCode=#{language}"

    Flowex.request(project, :post, url, body)
  end

  @doc """
  Add a training phrase to an intent.
  """
  @spec add_training_phrase(String.t, String.t, String.t, String.t) :: tuple
  def add_training_phrase(project, id, text, language \\ "en") do
    url = "intents/#{id}?languageCode=#{language}&intentView=INTENT_VIEW_FULL"

    with {:ok, intent} <- get(project, id, language, "INTENT_VIEW_FULL") do
      intent
      |> Map.get("trainingPhrases")
      |> set_training_phrase(text)
      |> (&Map.put(intent, "trainingPhrases", &1)).()
      |> (&Flowex.request(project, :patch, url, &1)).()
    end
  end

  @doc """
  Update an intent view full.
  """
  @spec update(String.t, String.t, map, String.t) :: tuple
  def update(project, id, intent, language \\ "es") do
    url = "intents/#{id}?languageCode=#{language}&intentView=INTENT_VIEW_FULL"

    Flowex.request(project, :patch, url, intent)
  end

  # ---------------------------------------------------------------------------
  # Define a training phrase.
  # ---------------------------------------------------------------------------
  @spec set_training_phrase(nil | list, String.t) :: list
  defp set_training_phrase(nil, text) do
    [%{
      "name" => UUID.uuid4(),
      "parts" => [%{"text" => text}],
      "type" => "EXAMPLE"
    }]
  end
  defp set_training_phrase(training_phrases, text) do
    [
      %{
        "name" => UUID.uuid4(),
        "parts" => [%{"text" => text}],
        "type" => "EXAMPLE"
      } || training_phrases
    ]
  end
end
