defmodule Glific.Notion do
  alias Glific.Registrations.Registration

  @doc """
  Utilities to interact with Notion
  """

  @ngo_database_id "2ba8364b6fa94f43b7d2b88bf6628a7d"

  @notion_base_url "https://api.notion.com/v1"
  require Logger
  use Tesla

  @spec headers() :: list()
  defp headers(),
    do: [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer " <> Application.get_env(:glific, :notion_secret)},
      {"Notion-Version", "2022-02-22"}
    ]

  @doc """
  Creates a new entry in notion ngo onboarded database
  """
  @spec create_database_entry(map()) :: {:ok, String.t()} | {:error, String.t()}
  def create_database_entry(properties) do
    with {:ok, %{"id" => page_id}} <- create_page(properties) |> IO.inspect() do
      {:ok, page_id}
    else
      {:error, message} ->
        Logger.error("Error on creating notion database entry due to #{message}")
        {:error, message}
    end
  end

  @spec update_database_entry(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def update_database_entry(page_id, properties) do
    with {:ok, _} <- update_page(page_id, properties) do
      {:ok, "success"}
    else
      {:error, message} ->
        Logger.error("Error on creating notion database entry due to #{message}")
        {:error, message}
    end
  end

  @spec init_table_properties(Registration.t()) :: map()
  def init_table_properties(registration) do
    %{
      "Org Name" => %{
        "type" => "title",
        "title" => [
          %{"type" => "text", "text" => %{"content" => "#{registration.org_details.name}"}}
        ]
      },
      "terms agreed" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "No"}
          }
        ]
      }
      # "NGO POC email id" => %{
      #   "type" => "rich_text",
      #   "rich_text" => %{
      #     "type" => "text",
      #     "text" => %{"content" => "#{registration.org_details["email"]}"}
      #   }
      # },
      # "Current office location- City" => %{
      #   "type" => "rich_text",
      #   "rich_text" => %{
      #     "type" => "text",
      #     "text" => %{"content" => "#{registration.org_details["current_address"]}"}
      #   }
      # },
      # "Finance POC Details" => %{
      #   "type" => "rich_text",
      #   "rich_text" => %{
      #     "type" => "text",
      #     "text" => %{"content" => "#{convert_details_to_string(registration.finance_poc)}"}
      #   }
      # },
      # "BOT number" => %{
      #   "type" => "number",
      #   "number" => registration.platform_details["phone"]
      # }
    }
  end

  @spec update_table_properties(Registration.t()) :: map()
  def update_table_properties(registration) do
    %{
      "Org Name" => %{
        "type" => "title",
        "title" => [
          %{"type" => "text", "text" => %{"content" => "#{registration.org_details["name"]}"}}
        ]
      },
      "terms agreed" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{"content" => "No"}
          }
        ]
      },
      "NGO POC email id" => %{
        "type" => "rich_text",
        "rich_text" => %{
          "type" => "text",
          "text" => [%{"content" => "#{registration.org_details["email"]}"}]
        }
      },
      "Current office location- City" => %{
        "type" => "rich_text",
        "rich_text" => %{
          "type" => "text",
          "text" => [%{"content" => "#{registration.org_details["current_address"]}"}]
        }
      },
      "Finance POC Details" => %{
        "type" => "rich_text",
        "rich_text" => %{
          "type" => "text",
          "text" => [%{"content" => "#{convert_details_to_string(registration.finance_poc)}"}]
        }
      },
      "BOT number" => %{
        "type" => "number",
        "number" => registration.platform_details["phone"]
      }
    }
  end

  @spec create_page(map()) :: {:ok, map()} | {:error, String.t()}
  defp create_page(properties) do
    body = %{
      parent: %{
        database_id: @ngo_database_id
      },
      properties: properties
    }

    post(@notion_base_url <> "/pages", Jason.encode!(body), headers: headers())
    |> parse_response()
  end

  @spec update_page(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  defp update_page(page_id, properties) do
    body = %{
      properties: properties
    }

    patch(@notion_base_url <> "/pages/#{page_id}", body, headers: headers())
    |> parse_response()
  end

  @spec parse_response(Tesla.Env.result()) :: {:ok, map()} | {:error, String.t()}
  defp parse_response({:ok, %{body: resp_body, status: status}})
       when status >= 200 and status < 300 do
    {:ok, resp_body}
  end

  defp parse_response({:ok, %{body: resp_body}}) do
    {:error, inspect(resp_body)}
  end

  defp parse_response({:error, message}), do: {:error, inspect(message)}

  @spec convert_details_to_string(map()) :: String.t()
  defp convert_details_to_string(details) do
    details
    |> Enum.reduce("", fn {k, v}, str ->
      str <> "| #{k}: #{v} "
    end)
  end
end
