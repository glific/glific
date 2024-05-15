defmodule Glific.Notion do
  alias Glific.Partners.Organization
  alias Glific.Registrations.Registration

  @doc """
  Utilities to interact with Notion
  """

  @ngo_database_id "ebfc67ca718549729861aa8a25ebe296"
  @ngo_page_id "880ec3558287464fbd6f1688435e33de"

  @notion_base_url "https://api.notion.com/v1"

  use Tesla

  @spec headers() :: list()
  defp headers(),
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
    with {:ok, %{"properties" => properties} = database} <- fetch_database() do
    end
  end

  @spec fetch_database :: {:ok, map()} | {:error, String.t()}
  defp fetch_database do
    (@notion_base_url <> "/databases/#{@ngo_database_id}")
    |> get(headers: headers())
    |> parse_response()
  end

  @spec create_page(map()) :: {:ok, map()} | {:error, String.t()}
  defp create_page(properties) do
    body = %{
      parent: %{
        database_id: @ngo_database_id
      },
      properties: properties
    }

    post(@notion_base_url <> "/pages", body)
    |> parse_response()
  end

  @spec parse_response(Tesla.Env.result()) :: {:ok, map()} | {:error, String.t()}
  defp parse_response({:ok, %{body: resp_body, status: status}})
       when status >= 200 and status < 300 do
    {:ok, resp_body}
  end

  defp parse_response({:ok, %{body: resp_body, status: status}}) do
    {:error, inspect(resp_body)}
  end

  defp parse_response({:error, message}, _), do: {:error, inspect(message)}

  defp create_table_properties(org, %Registration{} = registration) do
    %{
      "Org Name" => %{
        "type" => "title",
        "title" => [
          %{"type" => "text", "text" => %{"content" => "#{registration.org_details["name"]}"}}
        ]
      },
      "NGO POC email id" => %{
        "type" => "rich_text",
        "rich_text" => %{
          "type" => "text",
          "text" => %{"content" => "#{registration.org_details["email"]}"}
        }
      },
      "Current office location- City" => %{
        "type" => "rich_text",
        "rich_text" => %{
          "type" => "text",
          "text" => %{"content" => "#{registration.org_details["current_address"]}"}
        }
      },
      "Finance POC Details" => %{
        "type" => "rich_text",
        "rich_text" => %{
          "type" => "text",
          "text" => %{"content" => "#{convert_details_to_string(registration.finance_poc)}"}
        }
      },
      "BOT number" => %{
        "type" => "number",
        "number" => "345"
      }
      # TODO: add the bot number
    }
  end

  @spec convert_details_to_string(map()) :: String.t()
  defp convert_details_to_string(details) do
    details
    |> Enum.reduce("", fn {k, v}, str ->
      str <> "| #{k}: #{v} "
    end)
  end
end
