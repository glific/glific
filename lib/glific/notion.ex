defmodule Glific.Notion do
  @doc """
  Utilities to interact with Notion
  """

  @ngo_database_id "ebfc67ca718549729861aa8a25ebe296"
  @ngo_page_id "880ec3558287464fbd6f1688435e33de"

  @notion_base_url "https://api.notion.com/v1"

  use Tesla

  @spec headers(String.t()) :: list()
  defp headers(token),
    do: [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer " <> Application.get_env(:glific, :google_translate)}
    ]

  @doc """
  Creates a new entry in notion ngo onboarded database
  """
  @spec create_database_entry(Registration.t()) :: {:ok, String.t()} | {:error, String.t()}
  def create_database_entry(registration) do
    # fetch the database schema
    # Make the payload for the entry
    # create page
    # then hit post req
    # handle the response
  end

  @spec fetch_database :: {:ok, map()} | {:error, String.t()}
  defp fetch_database do

  end
end
